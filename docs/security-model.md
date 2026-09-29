# Security model

## Vault EC2 identity

Vault nodes will use a dedicated IAM role assumed by the EC2 service. This gives instances temporary credentials rather than static AWS keys. The role is created without attached policies; assuming it alone grants no access to KMS, S3, or other AWS services.

The instance profile and its attachment belong to the EC2 stage. When the customer-managed KMS key exists, grant only the actions Vault needs on that key and review both its IAM policy and key policy. Nodes must also have a private network path to KMS before auto-unseal can work.

## Validation

Check that the role trust policy permits only the EC2 service to assume the role and that no permissions policies are attached. Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Role creation alone does not validate auto-unseal; test that after instances, Vault configuration, and KMS connectivity exist.
