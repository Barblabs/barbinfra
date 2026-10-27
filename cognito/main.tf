locals {
  name = "barbattack-${var.environment}"
}

# One pool for the Users of every Customer and for Platform Admins (barbackend
# ADR 0013). Cognito only proves who a User is; Customer and role live in
# barbackend's Postgres, keyed by the sub.
resource "aws_cognito_user_pool" "users" {
  name                = local.name
  user_pool_tier      = "LITE"
  deletion_protection = "ACTIVE"

  # barbackend's AdminCreateUser passes the email as the username.
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  auto_verified_attributes = ["email"]

  # Users are created only by barbackend, never by signing up.
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your barbattack account"
      email_message = "You have been invited to barbattack. Sign in with {username} and the temporary password {####}, then choose your own password."
      sms_message   = "Your barbattack username is {username} and temporary password is {####}."
    }
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  email_configuration {
    email_sending_account = var.ses_email_identity_arn == null ? "COGNITO_DEFAULT" : "DEVELOPER"
    source_arn            = var.ses_email_identity_arn
    from_email_address    = var.from_email_address
  }

  # Destroying the pool deletes every User and their subs, which barbackend's
  # users table cannot be reconciled with.
  lifecycle {
    prevent_destroy = true
  }
}

# The dashboard signs in from the browser, so the client is public and has no
# secret. barbackend checks this client's id in every access token.
resource "aws_cognito_user_pool_client" "dashboard" {
  name         = "${local.name}-dashboard"
  user_pool_id = aws_cognito_user_pool.users.id

  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  read_attributes = ["email", "email_verified"]
  # Users must not change their own email: barbackend stores it alongside the
  # sub and it is their username. Listing an attribute here is what stops the
  # client from writing all of them.
  write_attributes = ["name"]
}

# What barbackend needs to create and delete Users, attached to whichever role
# or user runs serve and create-platform-admin.
data "aws_iam_policy_document" "backend" {
  statement {
    actions = [
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminDeleteUser",
    ]
    resources = [aws_cognito_user_pool.users.arn]
  }
}

resource "aws_iam_policy" "backend" {
  name        = "${local.name}-backend-cognito"
  description = "Lets barbackend create and delete Users in the ${local.name} user pool."
  policy      = data.aws_iam_policy_document.backend.json
}
