# ==============================================================================
# VPC Resource Definition
# ==============================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                        = "${var.environment}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ==============================================================================
# Internet Gateway (IGW) for Public Subnets
# ==============================================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-igw"
  }
}

# ==============================================================================
# Public Subnets (For ALBs and NAT Gateways)
# ==============================================================================
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.environment}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Tag required by AWS Load Balancer Controller to discover public subnets for external ALBs:
    "kubernetes.io/role/elb" = "1"
  }
}

# ==============================================================================
# Private Subnets (For EKS Worker Nodes and Internal Workloads)
# ==============================================================================
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                        = "${var.environment}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Tag required by AWS Load Balancer Controller to discover private subnets for internal ALBs:
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter / Cluster Autoscaler subnet auto-discovery tag:
    "karpenter.sh/discovery" = var.cluster_name
  }
}

# ==============================================================================
# Elastic IPs for NAT Gateways
# ==============================================================================
resource "aws_eip" "nat" {
  count  = var.enable_ha_nat_gateway ? length(var.availability_zones) : 1
  domain = "vpc"

  tags = {
    Name = "${var.environment}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ==============================================================================
# NAT Gateways (Provides outbound internet access for private subnet workloads)
# ==============================================================================
resource "aws_nat_gateway" "nat" {
  count         = var.enable_ha_nat_gateway ? length(var.availability_zones) : 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.environment}-nat-${var.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ==============================================================================
# Routing: Public Route Table
# ==============================================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ==============================================================================
# Routing: Private Route Table(s)
# ==============================================================================
resource "aws_route_table" "private" {
  count  = var.enable_ha_nat_gateway ? length(var.availability_zones) : 1
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = {
    Name = "${var.environment}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count     = length(var.private_subnet_cidrs)
  subnet_id = aws_subnet.private[count.index].id
  # If HA NAT is enabled, map private subnet to its AZ's NAT; otherwise map all to single NAT:
  route_table_id = var.enable_ha_nat_gateway ? aws_route_table.private[count.index].id : aws_route_table.private[0].id
}
