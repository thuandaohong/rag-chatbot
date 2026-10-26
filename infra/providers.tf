terraform {
  required_version = ">= 1.10" # use_lockfile cần >= 1.10

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.56" # >= 6.56: hỗ trợ Knowledge Base loại MANAGED
    }
  }

  backend "s3" {
    bucket       = "rag-chatbot-tfstate-thuan-20261024"
    key          = "rag-chatbot/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # khóa state bằng file .tflock trên S3 (thay DynamoDB, TF >= 1.10)
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}
