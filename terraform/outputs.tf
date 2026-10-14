output "vault_recovery_secret_name" {
  description = "Name of the empty Secrets Manager secret for the Vault recovery bundle"
  value       = module.vault_recovery.secret_name
}

output "vault_recovery_kms_key_arn" {
  description = "Dedicated KMS key ARN encrypting the Vault recovery bundle"
  value       = module.vault_recovery.kms_key_arn
}
