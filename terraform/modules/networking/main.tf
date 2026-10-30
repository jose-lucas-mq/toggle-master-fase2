resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

# ----- Internet Gateway -----
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# ----- Sub-redes públicas (3 AZs) -----
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

# ----- Sub-redes privadas (3 AZs) -----
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_subnet_cidrs[count.index]
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

# ----- Route Table pública -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ----- EIPs (um por NAT Gateway) -----
locals {
  # Single NAT → 1 EIP. Multi NAT → 3 EIPs.
  nat_count  = var.single_nat_gateway ? 1 : length(var.azs)
  nat_az_idx = [for i in range(local.nat_count) : var.single_nat_gateway ? 0 : i]
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-eip-${count.index}" })
  lifecycle { create_before_destroy = true }
}

# ----- NAT Gateways -----
resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[local.nat_az_idx[count.index]].id
  tags          = merge(var.tags, { Name = "${var.name_prefix}-nat-${count.index}" })
  depends_on    = [aws_internet_gateway.this]
}

# ----- Route Tables privadas (1 por NAT, que pode ser 1 ou 3) -----
resource "aws_route_table" "private" {
  count  = local.nat_count
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }
  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-private-${count.index}" })
}

resource "aws_route_table_association" "private" {
  count     = length(var.azs)
  subnet_id = aws_subnet.private[count.index].id
  # Single NAT → todas privadas no mesmo RT (índice 0). Multi → RT == AZ.
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}
