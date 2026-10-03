# Security model

## Vault EC2 identity

Vault nodes use a dedicated IAM role assumed by the EC2 service. This gives instances temporary credentials rather than static AWS keys. An inline role policy permits only `kms:Encrypt`, `kms:Decrypt`, and `kms:DescribeKey` on the auto-unseal key ARN. It grants no access to other keys or S3.

An IAM instance profile packages the role for attachment to EC2. The launch template will reference the profile; creating it does not launch instances. Nodes must also have a private network path to KMS before auto-unseal can work.

## Auto-unseal key

Use a regional, symmetric customer-managed KMS key with an alias for Vault auto-unseal. Enable automatic rotation and a 30-day deletion waiting period; Terraform also prevents accidental key destruction. The key policy delegates authorization to IAM in this account; the node role's key-scoped policy supplies its usage permissions. No key-policy change is required for this grant.

KMS protects Vault's seal, not its Raft data or S3 snapshots. Losing access to this key can prevent nodes from unsealing after restart; rotation retains old key material, but deleting the key can make recovery impossible. Review any key-policy change or deletion separately. Vault nodes will need a private path to KMS before auto-unseal can be tested.

## Validation

Check that the role trust policy permits only EC2 to assume the role. Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm the plan adds only the role's key-scoped IAM policy, with no changes to the KMS key or other resources. Terraform validation does not prove auto-unseal; test permitted key use and denied access to other keys after an instance profile and KMS network path exist, then test unseal after Vault is configured.
