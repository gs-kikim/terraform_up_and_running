terraform {
 required_providers {
   aws = {
     source  = "hashicorp/aws"  
     version = "~> 5.0"         
   }
 }
}

provider "aws" {
 region = "ap-southeast-1"
}

# Launch Configuration을 Launch Template으로 변경
resource "aws_launch_template" "example" {
  name_prefix   = "terraform-example"
  image_id      = "ami-0df7a207adb9748c7"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(templatefile("user-data.sh", {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  }))

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group 수정
resource "aws_autoscaling_group" "example" {
  name                = "terraform-asg-example"
  vpc_zone_identifier = data.aws_subnets.default.ids

  # Launch Template 참조로 변경
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key                 = "Name"
    value              = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance" {
 name = var.instance_security_group_name

 ingress {
   from_port   = var.server_port
   to_port     = var.server_port
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

 egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }

 tags = {
   Name = var.instance_security_group_name
 }
}

resource "aws_lb" "example" {
 name               = var.alb_name
 load_balancer_type = "application"
 subnets            = data.aws_subnets.default.ids
 security_groups    = [aws_security_group.alb.id]

 tags = {
   Environment = "example"
 }
}

resource "aws_lb_listener" "http" {
 load_balancer_arn = aws_lb.example.arn
 port              = 80
 protocol          = "HTTP"

 default_action {
   type = "fixed-response"

   fixed_response {
     content_type = "text/plain"
     message_body = "404: page not found"
     status_code  = 404
   }
 }
}

resource "aws_lb_target_group" "asg" {
 name     = var.alb_name
 port     = var.server_port
 protocol = "HTTP"
 vpc_id   = data.aws_vpc.default.id

 health_check {
   path                = "/"
   protocol            = "HTTP"
   matcher             = "200"
   interval            = 15
   timeout             = 3
   healthy_threshold   = 2
   unhealthy_threshold = 2
 }

 tags = {
   Name = var.alb_name
 }
}

resource "aws_lb_listener_rule" "asg" {
 listener_arn = aws_lb_listener.http.arn
 priority     = 100

 condition {
   path_pattern {
     values = ["*"]
   }
 }

 action {
   type             = "forward"
   target_group_arn = aws_lb_target_group.asg.arn
 }
}

resource "aws_security_group" "alb" {
 name = var.alb_security_group_name

 ingress {
   from_port   = 80
   to_port     = 80
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

 egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }

 tags = {
   Name = var.alb_security_group_name
 }
}

data "terraform_remote_state" "db" {
 backend = "s3"

 config = {
   bucket = var.db_remote_state_bucket
   key    = var.db_remote_state_key
   region = "ap-southeast-1"
 }
}

data "aws_vpc" "default" {
 default = true
}

data "aws_subnets" "default" {
 filter {
   name   = "vpc-id"
   values = [data.aws_vpc.default.id]
 }
}