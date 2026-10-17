output "kms_key_arn" {
  description = "Dedicated KMS key ARN used to encrypt the Vault recovery bundle"
  value       = aws_kms_key.this.arn
}

output "secret_name" {
  description = "Name of the empty Vault recovery bundle secret"
  value       = aws_secretsmanager_secret.bootstrap_recovery.name
}

output "bootstrap_role_arn" {
  description = "ARN of the dedicated role allowed to write the initial Vault recovery bundle"
  value       = aws_iam_role.bootstrap.arn
}
