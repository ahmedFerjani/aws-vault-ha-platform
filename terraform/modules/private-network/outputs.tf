output "subnet_ids" {
  description = "Private subnet IDs keyed by availability zone"
  value       = { for az, subnet in aws_subnet.this : az => subnet.id }
}

output "route_table_id" {
  description = "The ID of the private route table"
  value       = aws_route_table.this.id
}
