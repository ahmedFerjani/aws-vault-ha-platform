# Security model

## Vault EC2 identity

Vault nodes will use a dedicated IAM role assumed by the EC2 service. This gives instances temporary credentials rather than static AWS keys. The role is created without attached policies; assuming it alone grants no access to KMS, S3, or other AWS services.

The instance profile and its attachment belong to the EC2 stage. When the customer-managed KMS key exists, grant only the actions Vault needs on that key and review both its IAM policy and key policy. Nodes must also have a private network path to KMS before auto-unseal can work.

## Auto-unseal key

Use a regional, symmetric customer-managed KMS key with an alias for Vault auto-unseal. Enable automatic rotation and a 30-day deletion waiting period; Terraform also prevents accidental key destruction. The key policy initially delegates management to this AWS account's IAM administrators; access must be controlled through their IAM policies. It does not grant the Vault node role key use yet. Scope that role's permissions to this key in the next step.

KMS protects Vault's seal, not its Raft data or S3 snapshots. Losing access to this key can prevent nodes from unsealing after restart; rotation retains old key material, but deleting the key can make recovery impossible. Review any key-policy change or deletion separately. Vault nodes will need a private path to KMS before auto-unseal can be tested.

## Validation

Check that the role trust policy permits only the EC2 service to assume the role and that no permissions policies are attached. Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm that only the key and alias are added and that the key policy does not grant Vault key access yet. Role and key creation do not validate auto-unseal; test that after instances, Vault configuration, and KMS connectivity exist.
