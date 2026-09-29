resource "aws_internet_gateway" "this" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-internet-gateway"
  }
}

resource "aws_subnet" "this" {
  for_each = { for subnet in var.subnets : subnet.az => subnet }

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-subnet-${each.value.az}"
  }
}

resource "aws_route_table" "this" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-public-route-table"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.this.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id      = each.value.id
  route_table_id = aws_route_table.this.id
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-sg"
  description = "Public Vault NLB traffic boundary"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS clients to the future TLS listener"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = {
    Name = "${var.name_prefix}-nlb-ingress-443"
  }
}

resource "aws_vpc_security_group_egress_rule" "vault" {
  for_each = var.vault_subnet_cidrs

  security_group_id = aws_security_group.this.id
  description       = "Vault API and health checks in private subnets"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 8200
  to_port           = 8200

  tags = {
    Name = "${var.name_prefix}-nlb-egress-8200-${each.value}"
  }
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.this : subnet.id]
  security_groups    = [aws_security_group.this.id]

  enable_deletion_protection = false

  tags = {
    Name = "${var.name_prefix}-nlb"
  }
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name_prefix}-tg"
  port        = 8200
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "HTTPS"
    path     = "/v1/sys/health?standbyok=true"
    matcher  = "200"
  }

  tags = {
    Name = "${var.name_prefix}-tg"
  }
}
