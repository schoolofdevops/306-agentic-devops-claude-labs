resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-app-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euo pipefail
    yum update -y
    yum install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
  USERDATA
  )

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_group_ids
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "northstar-app"
    }
  }

  tags = {
    Name = "${var.project}-${var.environment}-app-lt"
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project}-${var.environment}-app-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  health_check_type   = "ELB"
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-app-asg"
    propagate_at_launch = true
  }
}

resource "aws_lb" "app" {
  name               = "${var.project}-${var.environment}-app-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = var.security_group_ids

  tags = {
    Name = "${var.project}-${var.environment}-app-lb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project}-${var.environment}-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name = "${var.project}-${var.environment}-app-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
