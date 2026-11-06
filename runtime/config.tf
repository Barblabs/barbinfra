locals {
  # The last path segment is the env var name, so the deploy script can turn
  # every parameter under this path into a KEY=value line.
  backend_config_path = "/barbattack/${var.environment}/backend"

  backend_config = {
    COGNITO_REGION       = local.cognito.region
    COGNITO_USER_POOL_ID = local.cognito.user_pool_id
    COGNITO_CLIENT_ID    = local.cognito.client_id
    CORS_ALLOWED_ORIGINS = "https://${local.app_domain}"
    PORT                 = "8080"
  }

  backend_secrets = toset([
    "CREDENTIALS_KEY",
    "ANTHROPIC_API_KEY",
    "NVD_API_KEY",
  ])
}

resource "aws_ssm_parameter" "backend_config" {
  for_each = local.backend_config

  name  = "${local.backend_config_path}/${each.key}"
  type  = "String"
  value = each.value
}

# A person overwrites these with aws ssm put-parameter --overwrite. Ignoring the
# value keeps the real secrets out of Terraform state and stops the next apply
# from resetting them.
resource "aws_ssm_parameter" "backend_secret" {
  for_each = local.backend_secrets

  name  = "${local.backend_config_path}/${each.key}"
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}
