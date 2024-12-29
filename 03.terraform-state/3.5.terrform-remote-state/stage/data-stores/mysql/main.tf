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

terraform {
  backend "s3" {

    # This backend configuration is filled in automatically at test time by Terratest. If you wish to run this example
    # manually, uncomment and fill in the config below.

    bucket         = "terraform-state-bucket-test-1"
    key            = "stage/data-stores/mysql/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "TerraformState"
    encrypt        = true

  }
}

resource "aws_db_instance" "example" {
  identifier_prefix   = "terraform-up-and-running"
  engine             = "mysql"
  engine_version     = "8.0"
  allocated_storage  = 10
  instance_class     = "db.t3.micro"  # t2.micro에서 t3.micro로 변경
  username           = "admin"
  db_name            = var.db_name
  password           = var.db_password
  skip_final_snapshot = true

  tags = {
    Name       = "terraform-up-and-running-db"
    Managed_By = "Terraform"
  }
}
