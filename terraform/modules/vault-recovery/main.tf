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

resource "aws_secretsmanager_secret" "bootstrap_recovery" {
  name                    = "${var.name_prefix}/bootstrap-recovery"
  description             = "Vault recovery shares and temporary bootstrap root token"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.default_tags, {
    Name = "${var.name_prefix}-bootstrap-recovery"
  })
}

resource "aws_iam_role" "bootstrap" {
  name = "${var.name_prefix}-bootstrap-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = var.bootstrap_trusted_principal_arn
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.default_tags, {
    Name = "${var.name_prefix}-bootstrap-role"
  })
}

resource "aws_iam_role_policy" "bootstrap_recovery" {
  name = "${var.name_prefix}-bootstrap-recovery"
  role = aws_iam_role.bootstrap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteAndVerifyRecoverySecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:PutSecretValue"]
        Resource = aws_secretsmanager_secret.bootstrap_recovery.arn
      },
      {
        Sid      = "UseRecoveryKeyThroughSecretsManager"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.this.arn
        Condition = {
          StringEquals = {
            "kms:ViaService"                  = "secretsmanager.${var.region}.amazonaws.com"
            "kms:EncryptionContext:SecretARN" = aws_secretsmanager_secret.bootstrap_recovery.arn
          }
        }
      }
    ]
  })
}
