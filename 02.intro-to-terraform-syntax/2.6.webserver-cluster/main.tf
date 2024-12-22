# Terraform 설정 블록
# required_providers 블록에서 필요한 프로바이더를 선언하고 버전을 지정
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # 프로바이더의 소스 위치
      version = "~> 5.0"         # 프로바이더 버전 (5.x.x 버전 사용)
    }
  }
}

# AWS 프로바이더 설정
# 리전 설정 및 인증 정보를 지정
provider "aws" {
  region = "ap-southeast-1"  # 싱가포르 리전 사용
}

# Amazon Linux 2 AMI 데이터 소스
# 최신 Amazon Linux 2 AMI ID를 동적으로 가져옴
data "aws_ami" "amazon_linux_2" {
  most_recent = true         # 가장 최근 AMI 선택
  owners      = ["amazon"]   # Amazon에서 제공하는 AMI만 선택

  # AMI 이름으로 필터링
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]  # Amazon Linux 2 AMI 패턴
  }

  # 가상화 타입으로 필터링
  filter {
    name   = "virtualization-type"
    values = ["hvm"]  # HVM(Hardware Virtual Machine) 타입만 선택
  }
}

# VPC(Virtual Private Cloud) 생성
# 격리된 네트워크 환경 구성
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"        # VPC IP 대역
  enable_dns_hostnames = true                 # DNS 호스트네임 활성화
  enable_dns_support   = true                 # DNS 지원 활성화

  tags = {
    Name = "terraform-example-vpc"
  }
}

# 인터넷 게이트웨이 생성
# VPC가 인터넷과 통신할 수 있게 함
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id  # 연결할 VPC ID

  tags = {
    Name = "terraform-example-igw"
  }
}

# 가용영역(AZ) 데이터 소스
# 현재 리전의 사용 가능한 AZ 목록을 가져옴
data "aws_availability_zones" "available" {
  state = "available"  # 사용 가능한 AZ만 선택
}

# 퍼블릭 서브넷 생성
# 각 가용영역에 퍼블릭 서브넷을 생성
resource "aws_subnet" "public" {
  count                   = 2                                # 2개의 서브넷 생성
  vpc_id                  = aws_vpc.main.id                 # VPC ID
  cidr_block              = "10.0.${count.index + 1}.0/24"  # 서브넷 IP 대역
  availability_zone       = data.aws_availability_zones.available.names[count.index]  # AZ 할당
  map_public_ip_on_launch = true                           # 퍼블릭 IP 자동 할당

  tags = {
    Name = "terraform-example-public-subnet-${count.index + 1}"
  }
}

# 라우트 테이블 생성
# 네트워크 트래픽 라우팅 규칙 정의
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                # 모든 외부 트래픽
    gateway_id = aws_internet_gateway.main.id  # 인터넷 게이트웨이로 라우팅
  }

  tags = {
    Name = "terraform-example-public-rt"
  }
}

# 라우트 테이블 연결
# 서브넷과 라우트 테이블을 연결
resource "aws_route_table_association" "public" {
  count          = 2                           # 2개의 서브넷에 대해 연결
  subnet_id      = aws_subnet.public[count.index].id  # 서브넷 ID
  route_table_id = aws_route_table.public.id  # 라우트 테이블 ID
}

# Launch Template 생성
# EC2 인스턴스 시작을 위한 템플릿 정의
resource "aws_launch_template" "example" {
  name_prefix   = "terraform-example"          # 템플릿 이름 접두사
  image_id      = data.aws_ami.amazon_linux_2.id  # AMI ID
  instance_type = "t2.micro"                  # 인스턴스 타입

  # 네트워크 인터페이스 설정
  network_interfaces {
    associate_public_ip_address = true                 # 퍼블릭 IP 할당
    security_groups            = [aws_security_group.instance.id]  # 보안 그룹
  }

  # 사용자 데이터 스크립트 (Base64 인코딩 필요)
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup python3 -m http.server ${var.server_port} &
              EOF
  )

  lifecycle {
    create_before_destroy = true  # 교체 시 새로운 리소스 먼저 생성
  }
}

# Auto Scaling Group 생성
# EC2 인스턴스의 자동 확장/축소 관리
resource "aws_autoscaling_group" "example" {
  vpc_zone_identifier = aws_subnet.public[*].id  # 서브넷 ID 목록
  target_group_arns  = [aws_lb_target_group.asg.arn]  # 대상 그룹 ARN
  health_check_type  = "ELB"                    # 헬스 체크 타입
  min_size          = 2                         # 최소 인스턴스 수
  max_size          = 10                        # 최대 인스턴스 수

  # Launch Template 설정
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"  # 최신 버전 사용
  }

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true  # 인스턴스에 태그 전파
  }
}

# Application Load Balancer 생성
# 트래픽 분산을 위한 로드 밸런서
resource "aws_lb" "example" {
  name               = var.alb_name              # ALB 이름
  load_balancer_type = "application"            # ALB 타입
  subnets            = aws_subnet.public[*].id   # 서브넷 ID 목록
  security_groups    = [aws_security_group.alb.id]  # 보안 그룹

  tags = {
    Name = "terraform-asg-example"
  }
}

# ALB 리스너 생성
# 들어오는 트래픽을 처리하는 규칙 정의
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn  # ALB ARN
  port              = 80                  # 리스너 포트
  protocol          = "HTTP"              # 프로토콜

  # 기본 작업 (404 반환)
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# ALB 대상 그룹 생성
# 요청을 라우팅할 대상 정의
resource "aws_lb_target_group" "asg" {
  name     = var.alb_name        # 대상 그룹 이름
  port     = var.server_port     # 포트
  protocol = "HTTP"              # 프로토콜
  vpc_id   = aws_vpc.main.id     # VPC ID

  # 헬스 체크 설정
  health_check {
    path                = "/"      # 체크 경로
    protocol            = "HTTP"   # 프로토콜
    matcher             = "200"    # 성공 응답 코드
    interval            = 15       # 체크 간격
    timeout             = 3        # 타임아웃
    healthy_threshold   = 2        # 정상 임계값
    unhealthy_threshold = 2        # 비정상 임계값
  }
}

# ALB 리스너 규칙 생성
# 트래픽 라우팅 규칙 정의
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn  # 리스너 ARN
  priority     = 100                       # 규칙 우선순위

  # 경로 패턴 조건
  condition {
    path_pattern {
      values = ["*"]  # 모든 경로 매칭
    }
  }

  # 작업 정의 (대상 그룹으로 전달)
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# EC2 인스턴스 보안 그룹
# 인스턴스의 네트워크 접근 규칙
resource "aws_security_group" "instance" {
  name        = var.instance_security_group_name  # 보안 그룹 이름
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.main.id                  # VPC ID

  # 인바운드 규칙 (웹 서버 포트)
  ingress {
    from_port   = var.server_port  # 시작 포트
    to_port     = var.server_port  # 종료 포트
    protocol    = "tcp"            # 프로토콜
    cidr_blocks = ["0.0.0.0/0"]    # 모든 IP 허용
  }

  # 아웃바운드 규칙 (모든 트래픽 허용)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"            # 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-example-instance"
  }
}

# ALB 보안 그룹
# 로드 밸런서의 네트워크 접근 규칙
resource "aws_security_group" "alb" {
  name        = var.alb_security_group_name  # 보안 그룹 이름
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id             # VPC ID

  # 인바운드 규칙 (HTTP)
  ingress {
    from_port   = 80          # HTTP 포트
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드 규칙 (모든 트래픽 허용)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-example-alb"
  }
}
