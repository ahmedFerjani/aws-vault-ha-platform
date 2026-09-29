output "role_name" {
  description = "Vault EC2 role name for the future instance profile"
  value       = aws_iam_role.this.name
}
