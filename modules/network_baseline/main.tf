locals {
  public_subnets  = { for k, v in var.subnets : k => v if lower(v.type) == "public" }
  private_subnets = { for k, v in var.subnets : k => v if lower(v.type) == "private" }

  public_azs  = toset([for k, v in local.public_subnets : v.az])
  private_azs = toset([for k, v in local.private_subnets : v.az])

  public_subnet_keys_by_az = {
    for az in local.public_azs :
    az => [for k, v in local.public_subnets : k if v.az == az]
  }

  # Choose the first public subnet key per AZ (required for per_az NAT).
  public_subnet_key_by_az = {
    for az, keys in local.public_subnet_keys_by_az :
    az => keys[0]
  }

  # Select a deterministic "first" public subnet for single NAT
  public_subnet_keys_sorted = sort(keys(local.public_subnets))
  single_nat_public_subnet_key = length(local.public_subnet_keys_sorted) > 0 ? local.public_subnet_keys_sorted[0] : null
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  count  = length(local.public_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = lower(each.value.type) == "public"

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name_prefix}-${each.key}"
    Tier = lower(each.value.type)
  })
}

# ---------- Public route table ----------
resource "aws_route_table" "public" {
  count  = length(local.public_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
  })
}

resource "aws_route" "public_default" {
  count                  = length(local.public_subnets) > 0 ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public[0].id
}

# ---------- NAT Gateways ----------
resource "aws_eip" "nat" {
  for_each = var.nat_gateway_strategy == "per_az" ? local.public_subnet_key_by_az : {}

  domain = "vpc"
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eip-nat-${each.key}"
  })
}

resource "aws_nat_gateway" "per_az" {
  for_each = var.nat_gateway_strategy == "per_az" ? local.public_subnet_key_by_az : {}

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.value].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_eip" "nat_single" {
  count  = (var.nat_gateway_strategy == "single" && local.single_nat_public_subnet_key != null) ? 1 : 0
  domain = "vpc"
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eip-nat"
  })
}

resource "aws_nat_gateway" "single" {
  count = (var.nat_gateway_strategy == "single" && local.single_nat_public_subnet_key != null) ? 1 : 0

  allocation_id = aws_eip.nat_single[0].id
  subnet_id     = aws_subnet.this[local.single_nat_public_subnet_key].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------- Private route tables (one per private AZ) ----------
resource "aws_route_table" "private" {
  for_each = local.private_azs

  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-${each.key}"
  })
}

resource "aws_route" "private_default" {
  for_each = (var.nat_gateway_strategy == "none" || length(local.private_azs) == 0) ? {} : aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = var.nat_gateway_strategy == "per_az" ? aws_nat_gateway.per_az[each.key].id : aws_nat_gateway.single[0].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.value.az].id
}
