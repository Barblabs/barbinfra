output "region" {
  description = "barbackend's COGNITO_REGION."
  value       = var.region
}

output "user_pool_id" {
  description = "barbackend's COGNITO_USER_POOL_ID."
  value       = aws_cognito_user_pool.users.id
}

output "client_id" {
  description = "barbackend's COGNITO_CLIENT_ID, and the client the dashboard signs in with."
  value       = aws_cognito_user_pool_client.dashboard.id
}

output "issuer" {
  description = "Issuer of the pool's tokens, as barbackend derives it."
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
}

output "backend_policy_arn" {
  description = "IAM policy to attach to the identity barbackend runs as."
  value       = aws_iam_policy.backend.arn
}
