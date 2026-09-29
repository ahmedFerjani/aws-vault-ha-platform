output "key_arn" {
  description = "Vault auto-unseal KMS key ARN for future role permissions"
  value       = aws_kms_key.this.arn
}
