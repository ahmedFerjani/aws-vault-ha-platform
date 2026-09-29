output "nlb_security_group_id" {
  description = "Security group ID assigned to the NLB"
  value       = aws_security_group.nlb.id
}

output "vault_security_group_id" {
  description = "Security group ID to assign to Vault nodes when provisioned"
  value       = aws_security_group.vault.id
}
