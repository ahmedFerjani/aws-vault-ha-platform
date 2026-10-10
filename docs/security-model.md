# Security model

## Vault EC2 identity

Vault nodes use a dedicated IAM role assumed by the EC2 service. This gives instances temporary credentials rather than static AWS keys. An inline role policy permits only `kms:Encrypt`, `kms:Decrypt`, and `kms:DescribeKey` on the auto-unseal key ARN. It grants no access to other keys or S3.

An IAM instance profile packages the role for attachment to EC2; the launch template references it. The role also has `AmazonSSMManagedInstanceCore` for node registration. Operator/controller session permissions are separate; this target policy does not authorize the laptop to initiate sessions. Nodes currently reach AWS APIs through NAT-backed outbound HTTPS; KMS/EC2 interface endpoints remain planned.

## Auto-unseal key

Use a regional, symmetric customer-managed KMS key with an alias for Vault auto-unseal. Enable automatic rotation and a 30-day deletion waiting period; Terraform also prevents accidental key destruction. The key policy delegates authorization to IAM in this account; the node role's key-scoped policy supplies its usage permissions. No key-policy change is required for this grant.

KMS protects Vault's seal, not its Raft data or S3 snapshots. Losing access to this key can prevent nodes from unsealing after restart; rotation retains old key material, but deleting the key can make recovery impossible. Review any key-policy change or deletion separately. The current NAT/HTTPS path permits AWS API connectivity, but no live Vault seal operation has been tested. Preserve the original key when restoring initialized data; recreating its alias is insufficient.

## Validation

Check that the role trust policy permits only EC2 to assume the role. Run `terraform fmt -check`, `terraform validate`, and `terraform plan`; review IAM changes for least privilege and KMS changes separately. A plan with no changes was recorded after management-module cleanup on 2026-10-10. Terraform validation and SSM registration do not prove auto-unseal; test permitted key use and denied access to other keys, then unseal after safe startup/initialization is designed. SSH-over-SSM uses IAM for the tunnel, SSH keys for OS authentication, and verified host keys for server identity. CloudTrail session records are not SSH command-content logs.
