resource "aws_iam_role" "this" {
  name        = "${var.name_prefix}-ec2-role"
  description = "IAM identity for Vault EC2 nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "auto_unseal" {
  name = "${var.name_prefix}-auto-unseal"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      Resource = var.auto_unseal_key_arn
    }]
  })
}
