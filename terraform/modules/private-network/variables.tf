variable "name_prefix" {
  description = "Prefix used in private network naming"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where private subnets will be created"
  type        = string
}

variable "nat_gateway_ids" {
  description = "Public NAT Gateway IDs keyed by Availability Zone"
  type        = map(string)
}

variable "subnets" {
  description = "List of private subnet objects with az and cidr_block"
  type = list(object({
    az         = string
    cidr_block = string
  }))
}
