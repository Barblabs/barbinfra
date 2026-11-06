locals {
  name    = "barbattack-${var.environment}"
  shared  = data.terraform_remote_state.shared.outputs
  cognito = data.terraform_remote_state.cognito.outputs
}

# Reading the other projects' outputs keeps every value in one place, so nothing
# is copied by hand between projects.
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "barbattack-terraform-state"
    key    = "shared.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "cognito" {
  backend = "s3"
  config = {
    bucket = "barbattack-terraform-state"
    key    = "cognito/${var.environment}.tfstate"
    region = "us-east-1"
  }
}

data "cloudflare_zone" "main" {
  filter = {
    name = var.domain_name
  }
}
