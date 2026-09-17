output "cluster_name" {
  description = "The name of the provisioned EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL for Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security Group ID associated with the EKS cluster control plane."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security Group ID associated with the worker nodes."
  value       = module.eks.node_security_group_id
}

output "vpc_id" {
  description = "ID of the VPC created for EKS."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of Private Subnet IDs hosting the EKS nodes."
  value       = module.vpc.private_subnet_ids
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN used for Kubernetes Service Account IAM roles (IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Run this AWS CLI command to configure kubectl credentials for your new cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
