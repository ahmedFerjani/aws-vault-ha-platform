output "launch_template_id" {
  description = "Launch template ID for the Vault Auto Scaling Group"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest launch template version"
  value       = aws_launch_template.this.latest_version
}

output "autoscaling_group_name" {
  description = "Name of the Vault node Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}
