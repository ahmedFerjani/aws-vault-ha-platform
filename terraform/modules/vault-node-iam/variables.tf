variable "name_prefix" {
  description = "Prefix used in the Vault EC2 role name"
  type        = string
}

variable "auto_unseal_key_arn" {
  description = "ARN of the KMS key used for Vault auto-unseal"
  type        = string
}
