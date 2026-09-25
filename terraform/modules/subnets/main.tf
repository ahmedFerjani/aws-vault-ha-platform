resource "aws_subnet" "private" {
  for_each = { for subnet in var.subnets : subnet.az => subnet }

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-subnet-${each.value.az}"
  }
}
