data "aws_caller_identity" "me" {}

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource automatically
  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Environment = "demo"
    }
  }
}

terraform {
  backend "s3" {
    bucket       = "billy-joe-terraform-test-2026"
    key          = "event-driven-pipeline/terraform.tfstate" # MUST be unique per project
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true # S3-native locking (Terraform >= 1.10)
  }
}