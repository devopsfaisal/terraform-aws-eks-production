variable "aws_region" {
  description = "AWS region where all infrastructure resources will be provisioned."
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "The aws_region variable must follow standard AWS region naming (e.g. ap-south-1, us-east-1)."
  }
}

variable "environment" {
  description = "Environment identifier (e.g. production, staging, dev)."
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Name of the project used for resource naming and tagging."
  type        = string
  default     = "eks-production"
}

# --- VPC & Networking Variables ---
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of Availability Zones to deploy subnets into."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (used by ALBs and NAT Gateways)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (used by EKS Worker Nodes)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "enable_ha_nat_gateway" {
  description = "Enable 1 NAT Gateway per AZ for production High Availability. Set to false to use a single shared NAT Gateway and reduce AWS cost."
  type        = bool
  default     = false
}

# --- EKS Cluster Variables ---
variable "cluster_name" {
  description = "Name of the Amazon EKS cluster."
  type        = string
  default     = "eks-production-cluster"
}

variable "cluster_version" {
  description = "Kubernetes control plane version."
  type        = string
  default     = "1.36"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_groups" {
  description = "Map of EKS Managed Node Groups with sizing and instance configurations."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = number
    labels         = map(string)
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      disk_size      = 30
      labels = {
        role = "general-workloads"
      }
    }
  }
}
