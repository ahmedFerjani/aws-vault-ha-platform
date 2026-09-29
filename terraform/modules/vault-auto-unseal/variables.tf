variable "name_prefix" {
  description = "Prefix used in the Vault KMS key name and alias"
  type        = string
}

variable "account_id" {
  description = "AWS account ID allowed to delegate KMS administration through IAM"
  type        = string
}
