locals {
  instance_tags = merge(var.default_tags, {
    Name = "${var.name_prefix}-node"
  })

  volume_tags = merge(var.default_tags, {
    Name = "${var.name_prefix}-node-root"
  })
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-node-"
  description   = "Launch template for private Vault nodes"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [var.vault_security_group_id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.volume_tags
  }
}

resource "aws_autoscaling_group" "this" {
  name                = "${var.name_prefix}-nodes"
  min_size            = 0
  desired_capacity    = 1
  max_size            = 3
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }
}
