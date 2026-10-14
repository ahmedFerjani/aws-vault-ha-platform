resource "aws_kms_key" "this" {
  description              = "Vault recovery bundle encryption key"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  deletion_window_in_days  = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EnableAccountIAMAdministration"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action   = "kms:*"
      Resource = "*"
    }]
  })

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.default_tags, {
    Name = "${var.name_prefix}-recovery-key"
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}-recovery"
  target_key_id = aws_kms_key.this.key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret" "recovery_bundle" {
  name                    = "${var.name_prefix}/recovery-bundle"
  description             = "Vault recovery shares and temporary bootstrap root token"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.default_tags, {
    Name = "${var.name_prefix}-recovery-bundle"
  })
}
