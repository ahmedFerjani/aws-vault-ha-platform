variable "name_prefix" {
  description = "Prefix used in public network resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the public network resources"
  type        = string
}

variable "nlb_security_group_id" {
  description = "Security group ID assigned to the NLB"
  type        = string
}

variable "subnets" {
  description = "Public subnet CIDRs and Availability Zones"
  type = list(object({
    az         = string
    cidr_block = string
  }))
}
