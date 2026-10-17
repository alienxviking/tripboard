# Real AWS run: terraform plan -var-file=eks.tfvars
# Credentials come from `aws configure` (IAM user terraform-student), never from this file.
aws_region              = "ap-south-1"
use_localstack          = false
create_eks              = true
eks_version             = "1.36"
eks_node_instance_types = ["m7i-flex.large"]
eks_node_count          = 2
