resource "aws_subnet" "this" {
  for_each = { for subnet in var.subnets : subnet.az => subnet }

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-subnet-${each.value.az}"
  }
}

resource "aws_route_table" "this" {
  for_each = aws_subnet.this

  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-private-route-table-${each.key}"
  }
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id      = each.value.id
  route_table_id = aws_route_table.this[each.key].id
}

resource "aws_route" "nat_egress" {
  for_each = aws_route_table.this

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_ids[each.key]
}
