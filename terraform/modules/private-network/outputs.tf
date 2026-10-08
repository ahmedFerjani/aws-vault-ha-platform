output "subnet_ids" {
  description = "Private subnet IDs keyed by availability zone"
  value       = { for az, subnet in aws_subnet.this : az => subnet.id }
}

output "subnet_cidr_blocks" {
  description = "Private subnet CIDR blocks keyed by availability zone"
  value       = { for az, subnet in aws_subnet.this : az => subnet.cidr_block }
}

output "route_table_ids" {
  description = "Private route table IDs keyed by availability zone"
  value       = { for az, route_table in aws_route_table.this : az => route_table.id }
}
