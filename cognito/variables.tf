variable "region" {
  description = "AWS region of the user pool. barbackend reads it as COGNITO_REGION."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment, such as dev or prod. Part of every resource name."
  type        = string
}

variable "ses_email_identity_arn" {
  description = "ARN of a verified SES identity to send invitations from. Null uses Cognito's built-in email, which is limited to a few emails a day."
  type        = string
  default     = null
}

variable "from_email_address" {
  description = "From address for invitations sent through SES, such as \"barbattack <no-reply@example.com>\". Only used with ses_email_identity_arn."
  type        = string
  default     = null
}
