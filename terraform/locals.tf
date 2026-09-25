locals {
  default_tags = {
    Project     = "vault-ha"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "Ahmed Ferjani"
  }

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  name_prefix = lower("${var.project_name}-${var.environment}")
}
