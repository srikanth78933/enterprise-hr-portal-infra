# Three-tier VPC: frontend (public), compute (private) and data (isolated) subnets in every AZ.

data "aws_region" "current" {}

locals {
  az_count  = length(var.azs)
  nat_count = var.single_nat_gateway ? 1 : local.az_count
  # Short AZ suffix for names: ap-south-1a -> a
  az_suffix = [for az in var.azs : substr(az, -1, 1)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

# ---------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------
resource "aws_subnet" "frontend" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.frontend_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-frontend-${local.az_suffix[count.index]}"
    Tier = "frontend"
    # Lets the AWS Load Balancer Controller place internet-facing ALBs here
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "compute" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.compute_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-compute-${local.az_suffix[count.index]}"
    Tier = "compute"
    # Lets the AWS Load Balancer Controller place internal load balancers here
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "data" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-data-${local.az_suffix[count.index]}"
    Tier = "data"
  }
}

# ---------------------------------------------------------------
# NAT gateways (outbound internet for the compute subnets)
# ---------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = { Name = "${var.name}-nat-${local.az_suffix[count.index]}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.frontend[count.index].id

  tags = { Name = "${var.name}-nat-${local.az_suffix[count.index]}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------
# Frontend: default route to the Internet Gateway
resource "aws_route_table" "frontend" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-frontend-rt" }
}

resource "aws_route_table_association" "frontend" {
  count          = local.az_count
  subnet_id      = aws_subnet.frontend[count.index].id
  route_table_id = aws_route_table.frontend.id
}

# Compute: one route table per AZ, default route to the NAT gateway (in the same AZ when there is one per AZ)
resource "aws_route_table" "compute" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = { Name = "${var.name}-compute-${local.az_suffix[count.index]}-rt" }
}

resource "aws_route_table_association" "compute" {
  count          = local.az_count
  subnet_id      = aws_subnet.compute[count.index].id
  route_table_id = aws_route_table.compute[count.index].id
}

# Data: no default route at all, so the database can never reach or be reached from the internet
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-data-rt" }
}

resource "aws_route_table_association" "data" {
  count          = local.az_count
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# ---------------------------------------------------------------
# VPC endpoints
# ---------------------------------------------------------------
# S3 gateway endpoint is free and keeps S3 traffic off the NAT gateway
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.compute[*].id

  tags = { Name = "${var.name}-s3-endpoint" }
}

# Interface endpoints keep calls to Secrets Manager, STS (IRSA) and CloudWatch Logs inside the VPC
resource "aws_security_group" "endpoints" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name        = "${var.name}-vpce-sg"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count             = var.enable_interface_endpoints ? 1 : 0
  security_group_id = aws_security_group.endpoints[0].id
  cidr_ipv4         = var.cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = var.enable_interface_endpoints ? toset(["secretsmanager", "sts", "logs"]) : toset([])
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.compute[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.name}-${each.key}-endpoint" }
}
