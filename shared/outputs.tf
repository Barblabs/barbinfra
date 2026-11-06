output "ecr_repository_url" {
  description = "Registry path barbackend's images are pushed to and the instance pulls from."
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_arn" {
  description = "ARN the backend deploy role may push to."
  value       = aws_ecr_repository.backend.arn
}

output "github_oidc_provider_arn" {
  description = "Federated principal the GitHub deploy roles trust."
  value       = aws_iam_openid_connect_provider.github.arn
}
