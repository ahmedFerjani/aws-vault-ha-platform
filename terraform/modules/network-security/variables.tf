variable "name_prefix" {
  description = "Prefix used in security group names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the security groups"
  type        = string
}

variable "vault_subnet_cidrs" {
  description = "Private Vault subnet CIDRs allowed as NLB backend destinations"
  type        = set(string)
}
