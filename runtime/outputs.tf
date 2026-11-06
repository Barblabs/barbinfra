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
