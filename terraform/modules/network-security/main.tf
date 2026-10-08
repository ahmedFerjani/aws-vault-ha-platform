# NLB: public client ingress and private Vault API egress.
resource "aws_security_group" "nlb" {
  name        = "${var.name_prefix}-nlb-sg"
  description = "Public Vault NLB traffic boundary"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-nlb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.nlb.id
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

  security_group_id = aws_security_group.nlb.id
  description       = "Vault API and health checks in private subnets"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 8200
  to_port           = 8200

  tags = {
    Name = "${var.name_prefix}-nlb-egress-8200-${each.value}"
  }
}

# Vault nodes: NLB access and communication between cluster members.
resource "aws_security_group" "vault" {
  name        = "${var.name_prefix}-vault-sg"
  description = "Private Vault node traffic boundary"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-vault-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.nlb.id
  description                  = "NLB to Vault API and health checks"
  ip_protocol                  = "tcp"
  from_port                    = 8200
  to_port                      = 8200

  tags = {
    Name = "${var.name_prefix}-vault-ingress-nlb-8200"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.vault.id
  description       = "HTTPS egress through NAT for package installation and updates"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = {
    Name = "${var.name_prefix}-vault-egress-https-443"
  }
}

# Allow Vault nodes in this group to exchange peer API (8200) and cluster (8201) traffic.
resource "aws_vpc_security_group_ingress_rule" "peer" {
  for_each = toset(["8200", "8201"])

  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  description                  = "Vault peer traffic on TCP ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)

  tags = {
    Name = "${var.name_prefix}-vault-ingress-peer-${each.value}"
  }
}

resource "aws_vpc_security_group_egress_rule" "peer" {
  for_each = toset(["8200", "8201"])

  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  description                  = "Vault peer traffic on TCP ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)

  tags = {
    Name = "${var.name_prefix}-vault-egress-peer-${each.value}"
  }
}
