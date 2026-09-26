output "route_table_id" {
  description = "The ID of the private route table"
  value       = aws_route_table.this.id
}
