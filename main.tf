# ==============================================================================
# Root Module - EKS Production Infrastructure Composition
# ==============================================================================

# 1. Networking Layer (VPC, Multi-AZ Subnets, NAT Gateways, Routing)
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  cluster_name          = var.cluster_name
  environment           = var.environment
  enable_ha_nat_gateway = var.enable_ha_nat_gateway
}

# 2. Identity & Access Management Layer (Control Plane & Node IAM Roles)
module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
  environment  = var.environment
}

# 3. Compute & Kubernetes Orchestration Layer (EKS Cluster, Nodes, KMS, OIDC, Add-ons)
module "eks" {
  source = "./modules/eks"

  cluster_name                         = var.cluster_name
  cluster_version                      = var.cluster_version
  environment                          = var.environment
  vpc_id                               = module.vpc.vpc_id
  subnet_ids                           = module.vpc.private_subnet_ids
  cluster_role_arn                     = module.iam.cluster_role_arn
  node_role_arn                        = module.iam.node_role_arn
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  node_groups                          = var.node_groups

  depends_on = [
    module.vpc,
    module.iam
  ]
}
