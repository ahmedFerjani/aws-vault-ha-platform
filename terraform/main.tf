module "vpc" {
  source      = "./modules/vpc"
  name_prefix = local.name_prefix

  cidr_block = "10.16.0.0/16"
}

module "private_network" {
  source      = "./modules/private-network"
  name_prefix = local.name_prefix

  vpc_id = module.vpc.vpc_id
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
