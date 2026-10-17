# --- AWS -------------------------------------------------------------------
# Points to LocalStack (AWS emulator) by default so the project runs without an AWS account.
# For a real account set use_localstack = false and use normal AWS credentials (aws configure / env vars).
provider "aws" {
  region = var.aws_region

  access_key                  = var.use_localstack ? "test" : null
  secret_key                  = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      ec2 = var.localstack_endpoint
      s3  = var.localstack_endpoint
      iam = var.localstack_endpoint
      sts = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      Project   = "tripboard"
      ManagedBy = "terraform"
      Owner     = "snehangshu"
    }
  }
}

# --- Kubernetes / Helm: talk to the cluster created in cluster.tf (kind) or eks.tf (EKS) ---
# kind uses client certificates, EKS uses a short-lived token from `aws eks get-token`.
locals {
  k8s_host        = var.create_eks ? aws_eks_cluster.main[0].endpoint : kind_cluster.this[0].endpoint
  k8s_ca          = var.create_eks ? base64decode(aws_eks_cluster.main[0].certificate_authority[0].data) : kind_cluster.this[0].cluster_ca_certificate
  k8s_client_cert = var.create_eks ? null : kind_cluster.this[0].client_certificate
  k8s_client_key  = var.create_eks ? null : kind_cluster.this[0].client_key
  eks_token_args  = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
}

provider "kubernetes" {
  host                   = local.k8s_host
  client_certificate     = local.k8s_client_cert
  client_key             = local.k8s_client_key
  cluster_ca_certificate = local.k8s_ca

  dynamic "exec" {
    for_each = var.create_eks ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.eks_token_args
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.k8s_host
    client_certificate     = local.k8s_client_cert
    client_key             = local.k8s_client_key
    cluster_ca_certificate = local.k8s_ca
    exec = var.create_eks ? {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.eks_token_args
    } : null
  }
}
