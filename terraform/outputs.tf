output "cluster" {
  value = var.create_eks ? "EKS ${aws_eks_cluster.main[0].name} (${aws_eks_cluster.main[0].version})" : "kind ${kind_cluster.this[0].name}"
}

output "kubeconfig_path" {
  value = var.create_eks ? "not used - run: aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region}" : kind_cluster.this[0].kubeconfig_path
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "eks_cluster_name" {
  value = var.create_eks ? aws_eks_cluster.main[0].name : "not created (create_eks = false)"
}

output "eks_endpoint" {
  value = var.create_eks ? aws_eks_cluster.main[0].endpoint : null
}

output "urls" {
  value = {
    app          = "http://tripboard.local"
    grafana      = "http://grafana.local"
    prometheus   = "http://prometheus.local"
    alertmanager = "http://alertmanager.local"
    argocd       = "http://argocd.local"
  }
}

# EKS: public IP of the edge node running ingress-nginx (point the *.local hosts at it)
data "aws_instances" "edge" {
  count                = var.create_eks ? 1 : 0
  instance_tags        = { "eks:cluster-name" = var.cluster_name, "eks:nodegroup-name" = "edge" }
  instance_state_names = ["running"]
  depends_on           = [aws_eks_node_group.edge]
}

output "edge_public_ip" {
  value = var.create_eks ? try(data.aws_instances.edge[0].public_ips[0], null) : null
}
