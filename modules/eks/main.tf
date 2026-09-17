# ==============================================================================
# 1. AWS KMS Customer Managed Key (CMK) for Kubernetes Secrets Encryption
# ==============================================================================
resource "aws_kms_key" "eks_secrets" {
  count                   = var.enable_cluster_encryption ? 1 : 0
  description             = "KMS Key for EKS Secrets Envelope Encryption (${var.cluster_name})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-kms-key"
  }
}

resource "aws_kms_alias" "eks_secrets" {
  count         = var.enable_cluster_encryption ? 1 : 0
  name          = "alias/${var.cluster_name}-secrets"
  target_key_id = aws_kms_key.eks_secrets[0].key_id
}

# ==============================================================================
# 2. Security Groups
# ==============================================================================

# Cluster Control Plane Security Group
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-control-plane-sg"
  description = "Security group for EKS cluster control plane communication with worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name                                        = "${var.cluster_name}-control-plane-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Worker Nodes Security Group
resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id

  tags = {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# --- Granular Ingress / Egress Rules ---

# Node to Node communication (All traffic between pods across nodes)
resource "aws_vpc_security_group_ingress_rule" "node_to_node" {
  security_group_id            = aws_security_group.node.id
  description                  = "Allow worker nodes to communicate with each other"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# Control plane to Node: Allow kubelet communication (port 10250)
resource "aws_vpc_security_group_ingress_rule" "cluster_to_node_kubelet" {
  security_group_id            = aws_security_group.node.id
  description                  = "Allow control plane to reach kubelets"
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
}

# Node to Control plane: Allow HTTPS to cluster API server (port 443)
resource "aws_vpc_security_group_ingress_rule" "node_to_cluster_api" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Allow worker nodes to reach Kubernetes API server"
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Control plane outbound to Node group
resource "aws_vpc_security_group_egress_rule" "cluster_egress_to_node" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Allow cluster control plane egress to nodes"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# Node outbound internet access (via NAT Gateway for pulling packages/images)
resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  security_group_id = aws_security_group.node.id
  description       = "Allow all outbound traffic from nodes"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ==============================================================================
# 3. Amazon EKS Cluster (Control Plane)
# ==============================================================================
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Production Best Practice: Full audit and operational control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  dynamic "encryption_config" {
    for_each = var.enable_cluster_encryption ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.eks_secrets[0].arn
      }
      resources = ["secrets"]
    }
  }

  tags = {
    Name = var.cluster_name
  }
}

# ==============================================================================
# 4. OpenID Connect (OIDC) Provider for IRSA (IAM Roles for Service Accounts)
# ==============================================================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.cluster_name}-irsa-oidc-provider"
  }
}

# ==============================================================================
# 5. Launch Template for Managed Node Groups (Enforcing IMDSv2 & Security)
# ==============================================================================
resource "aws_launch_template" "node" {
  name_prefix   = "${var.cluster_name}-node-template-"
  description   = "Launch template for EKS managed node groups with security baselines"
  instance_type = "t3.medium"

  vpc_security_group_ids = [aws_security_group.node.id]

  # Enforce IMDSv2 to protect against SSRF and credential extraction vulnerabilities
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                        = "${var.cluster_name}-worker-node"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# 6. EKS Managed Node Groups
# ==============================================================================
resource "aws_eks_node_group" "nodes" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-${each.key}-node-group"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  capacity_type = each.value.capacity_type

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  tags = {
    Name                                        = "${var.cluster_name}-${each.key}-node"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      launch_template[0].version
    ]
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}

# ==============================================================================
# 7. EKS Core Managed Add-ons
# ==============================================================================
# resolve_conflicts_on_create / resolve_conflicts_on_update = "OVERWRITE" ensures
# Terraform smoothly adopts AWS default add-ons during a clean one-go apply
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.nodes]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
