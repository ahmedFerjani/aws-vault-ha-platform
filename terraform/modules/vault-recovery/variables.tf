variable "name_prefix" {
  description = "Prefix used for the recovery KMS key, alias, and Secrets Manager secret"
  type        = string
}

variable "account_id" {
  description = "AWS account ID permitted to delegate recovery-key administration through IAM"
  type        = string
}

variable "default_tags" {
  description = "Shared project tags applied to recovery resources"
  type        = map(string)
}

variable "bootstrap_trusted_principal_arn" {
  description = "IAM user or role ARN allowed to assume the one-time Vault bootstrap role"
  type        = string
}

variable "region" {
  description = "AWS region containing the recovery KMS key and Secrets Manager secret"
  type        = string
}
