# barbinfra

Terraform for barbattack's AWS infrastructure.

## Requirements

- Terraform >= 1.10: `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`
- AWS CLI with credentials for the barbattack account: `brew install awscli`, then `aws configure` or `aws configure sso`

## Projects

- `bootstrap/` creates the `barbattack-terraform-state` S3 bucket that stores every other project's state. Applied once; its own state is local.
- `cognito/` is the user pool barbackend authenticates against. One state per environment.

## First-time setup (done once for the whole team)

```sh
cd bootstrap
terraform init
terraform apply
```

If `bootstrap/terraform.tfstate` is ever lost, do not re-apply. Re-adopt the bucket with
`terraform import aws_s3_bucket.state barbattack-terraform-state` (and the same for the other resources in `bootstrap/main.tf`).

## Working on an environment

```sh
cd cognito
terraform init -reconfigure -backend-config=dev.s3.tfbackend
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

For prod, use `prod.s3.tfbackend` and `prod.tfvars`. Always run `init -reconfigure` when switching environments, and make sure the backend and var file match.

State is locked during `plan` and `apply`, so two people cannot apply at the same time.

After applying, copy the outputs (`terraform output`) into barbackend's config and attach `backend_policy_arn` to the identity barbackend runs as.

## Email in prod

Cognito's built-in email is limited to about 50 emails a day. Prod should send through SES by setting `ses_email_identity_arn` and `from_email_address` in `prod.tfvars`, after verifying the domain in SES and getting SES production access.
