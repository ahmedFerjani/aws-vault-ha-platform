output "role_name" {
  description = "Vault EC2 role name for the future instance profile"
  value       = aws_iam_role.this.name
}

output "instance_profile_name" {
  description = "Instance profile name for the future Vault EC2 launch template"
  value       = aws_iam_instance_profile.this.name
}
