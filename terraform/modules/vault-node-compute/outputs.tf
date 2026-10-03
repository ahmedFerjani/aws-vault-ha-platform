output "launch_template_id" {
  description = "Launch template ID for the Vault Auto Scaling Group"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest launch template version"
  value       = aws_launch_template.this.latest_version
}
