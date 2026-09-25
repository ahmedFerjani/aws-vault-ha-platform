# Terraform

This directory contains the AWS infrastructure layer for the Vault platform.

## Current milestone

The immediate focus is the network foundation for the Vault environment.

### Planned components

- VPC
- Private subnets across three AZs
- Route tables and routing
- NAT configuration
- Security groups and network boundaries

### Validation approach

Changes are added incrementally and validated before moving to the next layer. The next step is the minimal Terraform network setup required to support the three-node Vault cluster.
