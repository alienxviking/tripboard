variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "use_localstack" {
  description = "true = LocalStack emulator on localhost:4566, false = real AWS"
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "cluster_name" {
  type    = string
  default = "tripboard"
}

variable "kubernetes_version" {
  description = "kindest/node image tag"
  type        = string
  default     = "v1.33.1"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.11.0/24", "10.30.12.0/24"]
}

variable "create_eks" {
  description = "Create an EKS cluster + node group (real AWS only - LocalStack community has no EKS API)"
  type        = bool
  default     = false
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}
