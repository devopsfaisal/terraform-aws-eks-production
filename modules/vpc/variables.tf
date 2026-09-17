variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets."
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for subnet discovery tags)."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "enable_ha_nat_gateway" {
  description = "If true, creates 1 NAT Gateway per AZ; if false, uses 1 shared NAT Gateway."
  type        = bool
  default     = false
}
