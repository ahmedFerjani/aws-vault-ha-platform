# Security model

## Vault EC2 identity

Vault nodes use a dedicated IAM role assumed by the EC2 service. This gives instances temporary credentials rather than static AWS keys. An inline role policy permits only `kms:Encrypt`, `kms:Decrypt`, and `kms:DescribeKey` on the auto-unseal key ARN. It grants no access to other keys or S3.

An IAM instance profile packages the role for attachment to EC2; the launch template references it. The role also has `AmazonSSMManagedInstanceCore` for node registration and region-limited `ec2:DescribeInstances` for Vault AWS peer discovery. Operator/controller SSM Run Command/session permissions are separate; the node role does not authorize the laptop to initiate sessions. Nodes currently reach AWS APIs through NAT-backed outbound HTTPS; KMS/EC2 interface endpoints remain planned.

## Auto-unseal key

Use a regional, symmetric customer-managed KMS key with an alias for Vault auto-unseal. Enable automatic rotation and a 30-day deletion waiting period; Terraform also prevents accidental key destruction. The key policy delegates authorization to IAM in this account; the node role's key-scoped policy supplies its usage permissions. No key-policy change is required for this grant.

KMS protects Vault's seal, not its Raft data or S3 snapshots. Losing access to this key can prevent nodes from unsealing after restart; rotation retains old key material, but deleting the key can make recovery impossible. Review any key-policy change or deletion separately. The operator reports the initialized node remained unsealed after a controlled restart; multi-node seal behavior is not yet tested. Preserve the original key when restoring initialized data; recreating its alias is insufficient.

## Recovery-bundle key

The recovery bundle is encrypted by a separate KMS key used through Secrets Manager. The controller assumes the dedicated bootstrap IAM role to write and verify the bundle; Vault EC2 instances have no access to the recovery secret or this key. The bootstrap role cannot retrieve secret values. A separate authorized break-glass identity is needed to read the combined shares/root-token bundle.

## Validation

Check that the Vault instance role trusts only EC2 and the bootstrap role trusts only the configured deployment principal. Review Terraform plans and IAM/KMS changes for least privilege. Terraform validation and SSM registration do not prove auto-unseal; the reported controlled restart is initial single-node evidence, not a multi-node/failure test. SSH-over-SSM uses IAM for the tunnel/Run Command, SSH keys for OS authentication, and verified host keys for server identity. CloudTrail session records are not SSH command-content logs.
