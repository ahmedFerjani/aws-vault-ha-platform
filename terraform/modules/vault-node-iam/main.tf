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
