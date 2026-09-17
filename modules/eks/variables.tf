variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Desired Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.36"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster and nodes are provisioned."
  type        = string
}

variable "subnet_ids" {
  description = "Private Subnet IDs where EKS cluster interfaces and node groups are placed."
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role for the EKS cluster control plane."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the IAM role for the EKS node groups."
  type        = string
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS public endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cluster_encryption" {
  description = "Enable envelope encryption of Kubernetes secrets using AWS KMS."
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "Map of managed node group specifications."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = number
    labels         = map(string)
  }))
}
