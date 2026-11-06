output "backend_aws_role_arn" {
  description = "barbackend GitHub variable AWS_ROLE_ARN: the role its production deploy job assumes."
  value       = aws_iam_role.backend_deploy.arn
}

output "backend_ecr_repository" {
  description = "barbackend GitHub variable ECR_REPOSITORY: the registry path its deploy job pushes to."
  value       = local.shared.ecr_repository_url
}

output "backend_instance_name" {
  description = "barbackend GitHub variable INSTANCE_NAME: the Name tag its deploy job targets with ssm send-command."
  value       = local.backend_instance_name
}

output "dashboard_aws_role_arn" {
  description = "Dashboard GitHub variable AWS_ROLE_ARN: the role its production deploy job assumes."
  value       = aws_iam_role.dashboard_deploy.arn
}

output "dashboard_s3_bucket" {
  description = "Dashboard GitHub variable S3_BUCKET: the bucket its deploy job syncs dist/ to."
  value       = aws_s3_bucket.dashboard.id
}

output "dashboard_cloudfront_distribution_id" {
  description = "Dashboard GitHub variable CLOUDFRONT_DISTRIBUTION_ID: the distribution its deploy job invalidates."
  value       = aws_cloudfront_distribution.dashboard.id
}

output "dashboard_vite_api_url" {
  description = "Dashboard GitHub variable VITE_API_URL: the API base URL baked into the build."
  value       = "https://${local.api_domain}"
}
