# barbinfra

Terraform for barbattack's AWS infrastructure.

## Requirements

- Terraform >= 1.10: `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`
- AWS CLI with credentials for the barbattack account: `brew install awscli`, then `aws configure` or `aws configure sso`

## Projects

- `bootstrap/` creates the `barbattack-terraform-state` S3 bucket that stores every other project's state. Applied once; its own state is local.
- `cognito/` is the user pool barbackend authenticates against. One state per environment.
- `shared/` holds what every environment uses: the GitHub OIDC provider and the `barbackend` ECR repository. One state for the account.
- `runtime/` runs an environment: the VPC, RDS Postgres, the backend instance with Caddy, the dashboard's bucket and CloudFront distribution, the GitHub deploy roles, and the `api` and `app` DNS records in Cloudflare. Only `prod` exists.

`runtime/` reads `shared/` and `cognito/` state directly, so apply in this order:

```text
bootstrap/  ->  shared/  ->  cognito/  ->  runtime/
```

## First-time setup (done once for the whole team)

```sh
cd bootstrap
terraform init
terraform apply
```

If `bootstrap/terraform.tfstate` is ever lost, do not re-apply. Re-adopt the bucket with
`terraform import aws_s3_bucket.state barbattack-terraform-state` (and the same for the other resources in `bootstrap/main.tf`).

`shared/` has a fixed state key and no var file:

```sh
cd shared
terraform init
terraform apply
```

## Working on an environment

```sh
cd cognito
terraform init -reconfigure -backend-config=dev.s3.tfbackend
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

For prod, use `prod.s3.tfbackend` and `prod.tfvars`. Always run `init -reconfigure` when switching environments, and make sure the backend and var file match.

State is locked during `plan` and `apply`, so two people cannot apply at the same time.

For local development, copy the dev pool's outputs (`terraform output`) into barbackend's config. In an environment with a runtime, `runtime/` writes them to SSM and attaches `backend_policy_arn` to the instance role, so nothing is copied by hand.

## Before applying runtime/

- `cognito/` is applied for the same environment.
- `barbattack.com` is registered with Cloudflare, which hosts its DNS.
- A Cloudflare API token with **Zone: Read** and **DNS: Edit** on that zone only is kept in the team password manager. The Cloudflare provider reads it from `CLOUDFLARE_API_TOKEN`: export it, or put `CLOUDFLARE_API_TOKEN=...` in a `.env` at the repo root (gitignored) and run `set -a; . ../.env; set +a` from `runtime/`.

```sh
cd runtime
terraform init -reconfigure -backend-config=prod.s3.tfbackend
terraform plan  -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

The first apply waits until ACM sees the `app` certificate's validation record in Cloudflare, and CloudFront takes several more minutes.

## After applying runtime/

### Set the backend's secrets

Terraform creates `CREDENTIALS_KEY`, `ANTHROPIC_API_KEY`, and `NVD_API_KEY` as placeholders and never reads them back, so their values stay out of state. Generate `CREDENTIALS_KEY` with `openssl rand -base64 32` and **store it in the team password manager first**: losing it makes every stored iTop credential unrecoverable. Then, for each of the three:

```sh
read -rs value    # paste the value; it stays out of shell history
aws ssm put-parameter --overwrite --type SecureString \
  --name /barbattack/prod/backend/CREDENTIALS_KEY --value "$value"
```

The instance reads them at each deploy, so a changed value takes effect at the next `barbackend-deploy`.

### First deploy

Until the first deploy the instance runs only Caddy. Push an arm64 image tagged with its git SHA from barbackend, then deploy it:

```sh
repo=$(terraform -chdir=runtime output -raw backend_ecr_repository)
aws ecr get-login-password | docker login --username AWS --password-stdin "${repo%%/*}"
docker buildx build --platform linux/arm64 -t "$repo:<sha>" --push .    # from barbackend

aws ssm send-command --document-name AWS-RunShellScript \
  --targets Key=tag:Name,Values=barbattack-prod-backend \
  --parameters commands="barbackend-deploy <sha>"
curl -i https://api.barbattack.com/ping
```

`barbackend-deploy` pulls the image, runs `migrate`, and restarts `serve` only if `migrate` succeeds. Read its output with `aws ssm get-command-invocation`. It records the tag in `/barbattack/prod/deploy/image_tag`, so a replaced instance comes back on the last release. Later releases go through barbackend's deploy job.

### GitHub environment variables

Set these as variables (not secrets) on each repo's `production` environment. Values come from `terraform output` in the project named.

| Repo | Variable | Source |
| --- | --- | --- |
| both | `AWS_REGION` | `us-east-1` |
| barbackend | `AWS_ROLE_ARN` | `runtime/` `backend_aws_role_arn` |
| barbackend | `ECR_REPOSITORY` | `runtime/` `backend_ecr_repository` |
| barbackend | `INSTANCE_NAME` | `runtime/` `backend_instance_name` |
| dashboard | `AWS_ROLE_ARN` | `runtime/` `dashboard_aws_role_arn` |
| dashboard | `S3_BUCKET` | `runtime/` `dashboard_s3_bucket` |
| dashboard | `CLOUDFRONT_DISTRIBUTION_ID` | `runtime/` `dashboard_cloudfront_distribution_id` |
| dashboard | `VITE_API_URL` | `runtime/` `dashboard_vite_api_url` |
| dashboard | `VITE_COGNITO_REGION` | `cognito/` (prod) `region` |
| dashboard | `VITE_COGNITO_USER_POOL_ID` | `cognito/` (prod) `user_pool_id` |
| dashboard | `VITE_COGNITO_CLIENT_ID` | `cognito/` (prod) `client_id` |

### Running the instance

- Shell access is through Session Manager, with no SSH: `aws ssm start-session --target <instance id>` (needs `brew install --cask session-manager-plugin`).
- Logs go to the CloudWatch log groups `/barbattack/prod/backend` and `/barbattack/prod/caddy`.
- Never turn on the Cloudflare proxy (orange cloud) for `api` or `app`. It cuts requests off at 100 seconds, which breaks 5-minute Sync and Analista requests, and it blocks Caddy's certificate challenge.
- Let's Encrypt issues at most 5 certificates a week for `api.barbattack.com`, and a replaced instance requests a new one. Any change to the instance's `user_data`, which includes everything in `runtime/templates/`, replaces the instance, so avoid applying those repeatedly.

## Email in prod

Cognito's built-in email is limited to about 50 emails a day. Prod should send through SES by setting `ses_email_identity_arn` and `from_email_address` in `prod.tfvars`, after verifying the domain in SES (its verification records go in Cloudflare, as DNS only) and getting SES production access.
