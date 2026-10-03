variable "name_prefix" {
  description = "Prefix used in Vault compute resource names"
  type        = string
}

variable "ami_id" {
  description = "Pinned Amazon Linux AMI ID for Vault nodes"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile attached to Vault nodes"
  type        = string
}

variable "vault_security_group_id" {
  description = "Security group assigned to Vault nodes"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by the Vault Auto Scaling Group"
  type        = list(string)
}

variable "target_group_arn" {
  description = "NLB target group ARN for automatic Vault instance registration"
  type        = string
}

variable "default_tags" {
  description = "Default tags applied to launched instances and volumes"
  type        = map(string)
}
