terraform {
  required_version = ">= 1.10"

  # The key comes from dev.s3.tfbackend or prod.s3.tfbackend so each
  # environment has its own state.
  backend "s3" {
    bucket       = "barbattack-terraform-state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "barbattack"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
