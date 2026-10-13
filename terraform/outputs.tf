output "kind_cluster_name" {
  value = kind_cluster.this.name
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
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

output "urls" {
  value = {
    app          = "http://tripboard.local"
    grafana      = "http://grafana.local"
    prometheus   = "http://prometheus.local"
    alertmanager = "http://alertmanager.local"
    argocd       = "http://argocd.local"
  }
}
