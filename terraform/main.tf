module "vpc" {
  source      = "./modules/vpc"
  name_prefix = local.name_prefix

  cidr_block = "10.16.0.0/16"
}

module "private_network" {
  source      = "./modules/private-network"
  name_prefix = local.name_prefix

  vpc_id          = module.vpc.vpc_id
  nat_gateway_ids = module.public_network.nat_gateway_ids
  subnets = [
    {
      az         = "us-east-1a"
      cidr_block = "10.16.1.0/24"
    },
    {
      az         = "us-east-1b"
      cidr_block = "10.16.2.0/24"
    },
    {
      az         = "us-east-1c"
      cidr_block = "10.16.3.0/24"
    }
  ]
}

module "network_security" {
  source = "./modules/network-security"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  vault_subnet_cidrs = values(module.private_network.subnet_cidr_blocks)
}

module "public_network" {
  source = "./modules/public-network"

  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  nlb_security_group_id = module.network_security.nlb_security_group_id
  subnets = [
    {
      az         = "us-east-1a"
      cidr_block = "10.16.101.0/24"
    },
    {
      az         = "us-east-1b"
      cidr_block = "10.16.102.0/24"
    },
    {
      az         = "us-east-1c"
      cidr_block = "10.16.103.0/24"
    }
  ]
}

module "vault_auto_unseal" {
  source = "./modules/vault-auto-unseal"

  name_prefix = local.name_prefix
  account_id  = local.account_id
}

module "vault_node_iam" {
  source = "./modules/vault-node-iam"

  name_prefix         = local.name_prefix
  auto_unseal_key_arn = module.vault_auto_unseal.key_arn
}

module "vault_node_compute" {
  source = "./modules/vault-node-compute"

  name_prefix             = local.name_prefix
  ami_id                  = var.vault_ami_id
  instance_type           = var.vault_instance_type
  instance_profile_name   = module.vault_node_iam.instance_profile_name
  vault_security_group_id = module.network_security.vault_security_group_id
  private_subnet_ids      = values(module.private_network.subnet_ids)
  target_group_arn        = module.public_network.target_group_arn
  default_tags            = local.default_tags
}
