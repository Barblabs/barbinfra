output "state_bucket" {
  description = "Bucket every other project's S3 backend points at."
  value       = aws_s3_bucket.state.id
}
