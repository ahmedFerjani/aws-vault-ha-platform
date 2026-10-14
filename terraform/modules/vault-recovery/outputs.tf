output "kms_key_arn" {
  description = "Dedicated KMS key ARN used to encrypt the Vault recovery bundle"
  value       = aws_kms_key.this.arn
}

output "secret_name" {
  description = "Name of the empty Vault recovery bundle secret"
  value       = aws_secretsmanager_secret.recovery_bundle.name
}
