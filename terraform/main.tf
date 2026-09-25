module "vpc" {
  source      = "./modules/vpc"
  name_prefix = local.name_prefix

  cidr_block = "10.0.0.0/16"
}

module "private_subnets" {
  source      = "./modules/subnets"
  name_prefix = local.name_prefix

  vpc_id = module.vpc.vpc_id
  subnets = [
    {
      az         = "us-east-1a"
      cidr_block = "10.0.1.0/24"
    },
    {
      az         = "us-east-1b"
      cidr_block = "10.0.2.0/24"
    },
    {
      az         = "us-east-1c"
      cidr_block = "10.0.3.0/24"
    }
  ]
}
