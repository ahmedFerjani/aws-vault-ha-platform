output "vault_recovery_secret_name" {
  description = "Name of the empty Secrets Manager secret for the Vault recovery bundle"
  value       = module.vault_recovery.secret_name
}

output "vault_recovery_kms_key_arn" {
  description = "Dedicated KMS key ARN encrypting the Vault recovery bundle"
  value       = module.vault_recovery.kms_key_arn
}

output "vault_bootstrap_role_arn" {
  description = "IAM role ARN for the one-time Vault bootstrap runner"
  value       = module.vault_recovery.bootstrap_role_arn
}
