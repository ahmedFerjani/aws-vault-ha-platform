output "subnet_ids" {
  description = "Public subnet IDs keyed by Availability Zone"
  value       = { for az, subnet in aws_subnet.this : az => subnet.id }
}

output "route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.this.id
}

output "internet_gateway_id" {
  description = "ID of the VPC Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "load_balancer_dns_name" {
  description = "DNS name of the public Vault NLB"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "ARN of the Vault NLB target group"
  value       = aws_lb_target_group.this.arn
}

output "nat_gateway_ids" {
  description = "Public NAT Gateway IDs keyed by Availability Zone"
  value       = { for az, nat in aws_nat_gateway.this : az => nat.id }
}
