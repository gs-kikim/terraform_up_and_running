terraform {
 required_providers {
   aws = {
     source  = "hashicorp/aws"
     version = "~> 5.0"
   }
 }
}

provider "aws" {
 region                   = "ap-southeast-1"
 shared_credentials_files = ["C:\\Users\\kyeongin\\.aws\\credentials"]
 profile                  = "default"
}

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
 most_recent = true
 owners      = ["amazon"]

 filter {
   name   = "name"
   values = ["amzn2-ami-hvm-*-x86_64-gp2"]
 }

 filter {
   name   = "virtualization-type"
   values = ["hvm"]
 }
}

# Create VPC
resource "aws_vpc" "main" {
 cidr_block           = "10.0.0.0/16"
 enable_dns_hostnames = true
 enable_dns_support   = true

 tags = {
   Name = "terraform-example-vpc"
 }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
 vpc_id = aws_vpc.main.id

 tags = {
   Name = "terraform-example-igw"
 }
}

# Create Public Subnet
resource "aws_subnet" "public" {
 vpc_id                  = aws_vpc.main.id
 cidr_block              = "10.0.1.0/24"
 availability_zone       = "ap-southeast-1a"
 map_public_ip_on_launch = true

 tags = {
   Name = "terraform-example-public-subnet"
 }
}

# Create Route Table
resource "aws_route_table" "public" {
 vpc_id = aws_vpc.main.id

 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.main.id
 }

 tags = {
   Name = "terraform-example-public-rt"
 }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public" {
 subnet_id      = aws_subnet.public.id
 route_table_id = aws_route_table.public.id
}

resource "aws_instance" "example" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              # Create web content
              echo "Hello, World" > index.html
              
              # Start Python web server
              nohup python3 -m http.server 8080 &
              
              # Add logging
              echo "Web server started on port 8080" >> /var/log/user-data.log
              EOF

  user_data_replace_on_change = true

  tags = {
    Name = "terraform-example"
  }
}

resource "aws_security_group" "instance" {
 name        = var.security_group_name
 description = "Security group for web server"
 vpc_id      = aws_vpc.main.id

 ingress {
   description = "Allow inbound HTTP access on port 8080"
   from_port   = 8080
   to_port     = 8080
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

 ingress {
   description = "Allow SSH access"
   from_port   = 22
   to_port     = 22
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
   Name = "allow-web"
 }
}

variable "security_group_name" {
 description = "The name of the security group"
 type        = string
 default     = "terraform-example-instance"
}

output "public_ip" {
 value       = aws_instance.example.public_ip
 description = "The public IP of the Instance"
}