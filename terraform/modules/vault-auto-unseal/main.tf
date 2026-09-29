resource "aws_kms_key" "this" {
  description              = "Vault auto-unseal key"
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

  tags = {
    Name = "${var.name_prefix}-unseal-key"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}-auto-unseal"
  target_key_id = aws_kms_key.this.key_id
}
