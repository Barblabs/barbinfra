locals {
  api_domain = "api.${var.domain_name}"

  # Outside backend_config_path so the tag never lands in serve's env.
  image_tag_parameter = "/barbattack/${var.environment}/deploy/image_tag"

  parameter_arn_prefix = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter"
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_cloudwatch_log_group" "caddy" {
  name              = "/barbattack/${var.environment}/caddy"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/barbattack/${var.environment}/backend"
  retention_in_days = 30
}

data "aws_iam_policy_document" "backend_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend" {
  name               = "${local.name}-backend"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json
}

resource "aws_iam_role_policy_attachment" "backend" {
  for_each = {
    session_manager = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ecr_pull        = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    cognito_admin   = local.cognito.backend_policy_arn
  }

  role       = aws_iam_role.backend.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "backend" {
  statement {
    sid     = "ReadConfig"
    actions = ["ssm:GetParametersByPath", "ssm:GetParameter"]
    # GetParametersByPath authorizes against the path itself, the rest against
    # each parameter under it.
    resources = [
      "${local.parameter_arn_prefix}${local.backend_config_path}",
      "${local.parameter_arn_prefix}${local.backend_config_path}/*",
    ]
  }

  statement {
    sid       = "TrackImageTag"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = ["${local.parameter_arn_prefix}${local.image_tag_parameter}"]
  }

  # SecureStrings use the AWS managed aws/ssm key. Its ARN is unknown until SSM
  # creates the key on first use, so the grant is limited to calls through SSM.
  statement {
    sid       = "DecryptConfig"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }

  statement {
    sid     = "WriteLogs"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "${aws_cloudwatch_log_group.caddy.arn}:*",
      "${aws_cloudwatch_log_group.backend.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "backend" {
  name   = "backend"
  role   = aws_iam_role.backend.id
  policy = data.aws_iam_policy_document.backend.json
}

resource "aws_iam_instance_profile" "backend" {
  name = "${local.name}-backend"
  role = aws_iam_role.backend.name
}

resource "aws_instance" "backend" {
  ami           = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type = "t4g.micro"

  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.backend.name
  # user_data reaches dnf, Docker Hub, and ECR before the Elastic IP is
  # attached, so the instance needs its own public IP at launch.
  associate_public_ip_address = true

  # T4g defaults to unlimited credits, which bills sustained CPU above the
  # baseline. Standard throttles instead, which suits this budget.
  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  # Hop limit 2 because the containers sit one hop past the host, and
  # barbackend gets its AWS credentials from IMDS.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region              = var.region
    rds_ca_url          = "https://truststore.pki.rds.amazonaws.com/${var.region}/${var.region}-bundle.pem"
    caddy_log_group     = aws_cloudwatch_log_group.caddy.name
    backend_log_group   = aws_cloudwatch_log_group.backend.name
    image_tag_parameter = local.image_tag_parameter
    caddyfile = templatefile("${path.module}/templates/Caddyfile.tftpl", {
      api_domain = local.api_domain
    })
    deploy_script = templatefile("${path.module}/templates/barbackend-deploy.sh.tftpl", {
      region              = var.region
      ecr_registry        = split("/", local.shared.ecr_repository_url)[0]
      ecr_repository_url  = local.shared.ecr_repository_url
      config_path         = local.backend_config_path
      db_secret_arn       = aws_db_instance.main.master_user_secret[0].secret_arn
      db_address          = aws_db_instance.main.address
      db_port             = aws_db_instance.main.port
      db_name             = aws_db_instance.main.db_name
      image_tag_parameter = local.image_tag_parameter
    })
    caddy_service      = file("${path.module}/templates/caddy.service")
    barbackend_service = file("${path.module}/templates/barbackend.service")
  })

  tags = {
    Name = "${local.name}-backend"
  }

  # A newer AMI would otherwise replace the instance at the next apply, taking
  # its Let's Encrypt certificate and the running release with it.
  lifecycle {
    ignore_changes = [ami]
  }

  # The role's grants must exist before first boot, when user_data and the
  # first deploy call SSM, ECR, and Secrets Manager.
  depends_on = [
    aws_iam_role_policy.backend,
    aws_iam_role_policy_attachment.backend,
  ]
}

# Keeps api.<domain> on the same address when the instance is replaced.
resource "aws_eip" "backend" {
  domain   = "vpc"
  instance = aws_instance.backend.id

  tags = {
    Name = "${local.name}-backend"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "cloudflare_dns_record" "api" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = local.api_domain
  type    = "A"
  content = aws_eip.backend.public_ip
  ttl     = 300
  # Cloudflare's proxy cuts requests off at 100 seconds, which breaks 5-minute
  # Sync and Analista requests, and it blocks Caddy's HTTP challenge.
  proxied = false
}
