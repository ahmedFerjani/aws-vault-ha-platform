data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_route53_zone" "public" {
  name         = "ahmedferjani.com."
  private_zone = false
}
