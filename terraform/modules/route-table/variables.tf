variable "name_prefix" {
  description = "Prefix used in route table naming"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where the route table will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs keyed by availability zone"
  type        = map(string)
}
