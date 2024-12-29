terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  cloud {
    organization = "terraform-up-and-running-kikim"

    workspaces {
      name = "terraform-state-test"
      # 또는 여러 워크스페이스를 패턴으로 관리하고 싶다면:
      # tags = ["team:devops", "env:prod"]
    }
  }
}

provider "aws" {
  region                   = "ap-southeast-1"
}

# terraform {
#   backend "s3" {

#     # This backend configuration is filled in automatically at test time by Terratest. If you wish to run this example
#     # manually, uncomment and fill in the config below.

#     # bucket         = "<YOUR S3 BUCKET>"
#     # key            = "<SOME PATH>/terraform.tfstate"
#     # region         = "us-east-2"
#     # dynamodb_table = "<YOUR DYNAMODB TABLE>"
#     # encrypt        = true

#   }
# }

resource "aws_instance" "example" {
  ami           = "ami-0df7a207adb9748c7"  # Amazon Linux 2023 AMI in ap-southeast-1
  instance_type = terraform.workspace == "default" ? "t2.medium" : "t2.micro"

  tags = {
    Name        = "Example-${terraform.workspace}"
    Environment = terraform.workspace
    Managed_By  = "Terraform"
  }
}
