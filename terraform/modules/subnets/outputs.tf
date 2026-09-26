output "subnet_ids" {
  description = "Private subnet IDs keyed by availability zone"
  value       = { for az, subnet in aws_subnet.this : az => subnet.id }
}
