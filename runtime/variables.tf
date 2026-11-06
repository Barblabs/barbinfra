variable "region" {
  description = "AWS region everything in this environment runs in."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment, such as prod. Part of every resource name and of the cognito state key."
  type        = string
}

variable "domain_name" {
  description = "Domain whose DNS lives in Cloudflare. The API is served at api.<domain> and the dashboard at app.<domain>."
  type        = string
}

variable "backend_github_subject" {
  description = "OIDC sub claim barbackend's deploy job presents, in GitHub's numeric-ID form: repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:ENV."
  type        = string
}

variable "dashboard_github_subject" {
  description = "OIDC sub claim the dashboard's deploy job presents, in GitHub's numeric-ID form: repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:ENV."
  type        = string
}
