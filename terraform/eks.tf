# EKS cluster + managed node group (real AWS). Used when create_eks = true,
# otherwise the local kind cluster in cluster.tf is created instead.
# Control plane endpoint is public (kubectl from my machine), worker nodes sit in the private subnets
# and reach the internet (GHCR, GitHub) through the NAT gateway.

data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# EKS Pod Identity: lets one Kubernetes service account assume one IAM role
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count              = var.create_eks ? 1 : 0
  name               = "${var.cluster_name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  count      = var.create_eks ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodes" {
  count              = var.create_eks ? 1 : 0
  name               = "${var.cluster_name}-eks-nodes"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each = var.create_eks ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])
  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = each.value
}

# only the EBS CSI controller gets EBS permissions (not every pod on the node)
resource "aws_iam_role" "ebs_csi" {
  count              = var.create_eks ? 1 : 0
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.create_eks ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_cluster" "main" {
  count    = var.create_eks ? 1 : 0
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.eks_version

  # access entries API; the IAM user running terraform becomes cluster admin
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# VPC CNI with the network policy agent on, so the chart's NetworkPolicy is enforced
resource "aws_eks_addon" "vpc_cni" {
  count                       = var.create_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  configuration_values        = jsonencode({ enableNetworkPolicy = "true" })
}

resource "aws_eks_addon" "kube_proxy" {
  count                       = var.create_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
}

# The agent declares hostPort 80 on every node, which blocks ingress-nginx (hostPort 80) on the
# edge node. Nothing on the edge node uses pod identity, so keep the agent off it
# (default affinity + "ingress-ready DoesNotExist").
resource "aws_eks_addon" "pod_identity" {
  count                       = var.create_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    affinity = {
      nodeAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [{
            matchExpressions = [
              { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
              { key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] },
              { key = "eks.amazonaws.com/compute-type", operator = "NotIn", values = ["fargate", "hybrid", "auto"] },
              { key = "ingress-ready", operator = "DoesNotExist" },
            ]
          }]
        }
      }
    }
  })
}

resource "aws_eks_node_group" "default" {
  count           = var.create_eks ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.eks_node_instance_types
  ami_type        = "AL2023_x86_64_STANDARD"
  disk_size       = 20

  scaling_config {
    desired_size = var.eks_node_count
    min_size     = var.eks_node_count
    max_size     = var.eks_node_count + 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.eks_nodes, aws_eks_addon.vpc_cni]
}

# This account is not allowed to create load balancers yet ("OperationNotPermitted: This AWS account
# currently does not support creating load balancers" - new free-plan account), so a LoadBalancer
# service stays <pending>. Workaround: one small "edge" node in a public subnet runs ingress-nginx
# with hostPort 80 (same idea as the kind setup). The taint keeps app pods off it.
resource "aws_eks_node_group" "edge" {
  count           = var.create_eks ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "edge"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = [aws_subnet.public[0].id]
  instance_types  = [var.eks_edge_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"
  disk_size       = 20

  labels = { "ingress-ready" = "true" }

  taint {
    key    = "dedicated"
    value  = "ingress"
    effect = "NO_SCHEDULE"
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  depends_on = [aws_iam_role_policy_attachment.eks_nodes, aws_eks_addon.vpc_cni]
}

# HTTP to the edge node only from the IPs in ingress_allowed_cidrs (default: nobody)
resource "aws_vpc_security_group_ingress_rule" "edge_http" {
  for_each          = var.create_eks ? toset(var.ingress_allowed_cidrs) : toset([])
  security_group_id = aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id
  description       = "HTTP to ingress-nginx on the edge node"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# these two need running nodes
resource "aws_eks_addon" "coredns" {
  count                       = var.create_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "ebs_csi" {
  count        = var.create_eks ? 1 : 0
  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi[0].arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [aws_eks_node_group.default, aws_eks_addon.pod_identity, aws_iam_role_policy_attachment.ebs_csi]
}

# default StorageClass for the postgres PVC: encrypted gp3 EBS volume
resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_eks ? 1 : 0
  metadata {
    name        = "gp3"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
  depends_on = [aws_eks_addon.ebs_csi]
}
