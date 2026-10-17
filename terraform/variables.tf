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
  description = "true = EKS cluster on real AWS instead of kind (LocalStack community has no EKS API)"
  type        = bool
  default     = false

  validation {
    condition     = !(var.create_eks && var.use_localstack)
    error_message = "create_eks needs real AWS: set use_localstack = false."
  }
}

variable "eks_version" {
  description = "keep this on a version in standard support - extended support costs 6x more per hour"
  type        = string
  default     = "1.36"
}

variable "eks_node_instance_types" {
  # free-tier eligible on the AWS free plan; 8 GiB + up to 29 pods per node with the VPC CNI
  type    = list(string)
  default = ["m7i-flex.large"]
}

variable "eks_node_count" {
  type    = number
  default = 2
}

variable "eks_edge_instance_type" {
  description = "small public node that runs ingress-nginx (no load balancer on this account)"
  type        = string
  default     = "t3.small"
}

variable "ingress_allowed_cidrs" {
  description = "who may reach the edge node on port 80 - pass your own IP with -var, don't commit it"
  type        = list(string)
  default     = []
}
