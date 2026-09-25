variable "vpc_id" {
  description = "The VPC ID where subnets will be created"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used in subnet naming"
  type        = string
}

variable "subnets" {
  description = "List of private subnet objects with az and cidr_block"
  type = list(object({
    az         = string
    cidr_block = string
  }))
}
