variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "vault-ha"
}

variable "vault_instance_type" {
  description = "Starter EC2 instance type for each Vault node"
  type        = string
  default     = "t3.medium"
}

variable "vault_ami_id" {
  description = "Pinned Amazon Linux 2023 x86_64 AMI ID for Vault nodes in us-east-1"
  type        = string
  default     = "ami-0d27e0fb3bac4d724"
}
