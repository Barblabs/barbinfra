terraform {
  required_version = ">= 1.10"

  # The key comes from prod.s3.tfbackend so each environment has its own state.
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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
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

# The token comes from CLOUDFLARE_API_TOKEN so it never sits in a file. It needs
# Zone: Read and DNS: Edit on the barbattack zone only.
provider "cloudflare" {}
