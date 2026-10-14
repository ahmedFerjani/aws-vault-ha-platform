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
