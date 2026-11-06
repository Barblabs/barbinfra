data "aws_availability_zones" "available" {
  state = "available"

  # Local and Wavelength zones need opting in and lack RDS, so only regular AZs.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # RDS subnet groups need at least two AZs, even for a single-AZ instance.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.name
  }
}

# The backend instance lives here behind its Elastic IP.
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)

  tags = {
    Name = "${local.name}-public-${local.azs[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The database lives here with no route to or from the internet.
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 10 + count.index)

  tags = {
    Name = "${local.name}-private-${local.azs[count.index]}"
  }
}

# An explicit table with only the local route, so the private subnets never
# pick up a route someone adds to the VPC's main table.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

# Only Caddy's ports are open. serve's 8080 and SSH stay closed; admin access
# goes through SSM Session Manager.
resource "aws_security_group" "backend" {
  name        = "${local.name}-backend"
  description = "barbackend instance: HTTP and HTTPS in, all out"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "backend_ipv4" {
  for_each = toset(["80", "443"])

  security_group_id = aws_security_group.backend.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "backend_ipv6" {
  for_each = toset(["80", "443"])

  security_group_id = aws_security_group.backend.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv6         = "::/0"
}

# barbackend must reach any iTop URL a Customer enters, so egress stays open.
resource "aws_vpc_security_group_egress_rule" "backend_ipv4" {
  security_group_id = aws_security_group.backend.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "backend_ipv6" {
  security_group_id = aws_security_group.backend.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# Terraform removes AWS's default allow-all egress rule from groups it creates,
# so the database has no egress.
resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "RDS Postgres: 5432 from the barbackend instance only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "database" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
