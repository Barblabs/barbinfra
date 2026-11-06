terraform {
  required_version = ">= 1.10"

  # One state for the whole account: these resources serve every environment.
  backend "s3" {
    bucket       = "barbattack-terraform-state"
    key          = "shared.tfstate"
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
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "barbattack"
      ManagedBy = "terraform"
    }
  }
}
