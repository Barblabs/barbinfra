locals {
  app_domain = "app.${var.domain_name}"
}

resource "aws_s3_bucket" "dashboard" {
  bucket = "${local.name}-dashboard"
}

resource "aws_s3_bucket_ownership_controls" "dashboard" {
  bucket = aws_s3_bucket.dashboard.id

  # OAC needs ACLs off: every object then belongs to the bucket owner, so the
  # bucket policy alone decides what CloudFront may read.
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "dashboard" {
  bucket = aws_s3_bucket.dashboard.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 rather than KMS, so CloudFront needs no key policy grant to read.
resource "aws_s3_bucket_server_side_encryption_configuration" "dashboard" {
  bucket = aws_s3_bucket.dashboard.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "dashboard_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.dashboard.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.dashboard.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.dashboard.arn,
      "${aws_s3_bucket.dashboard.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "dashboard" {
  bucket = aws_s3_bucket.dashboard.id
  policy = data.aws_iam_policy_document.dashboard_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.dashboard]
}

resource "aws_cloudfront_origin_access_control" "dashboard" {
  name                              = "${local.name}-dashboard"
  description                       = "CloudFront reads the dashboard bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront only accepts certificates from us-east-1, whatever var.region is.
resource "aws_acm_certificate" "app" {
  region            = "us-east-1"
  domain_name       = local.app_domain
  validation_method = "DNS"

  # The distribution holds the certificate, so a replacement must exist before
  # the old one can be released.
  lifecycle {
    create_before_destroy = true
  }
}

# ACM returns names and targets with a trailing dot, which Cloudflare drops;
# trimming it keeps the next plan from showing a diff.
resource "cloudflare_dns_record" "cert_validation" {
  for_each = {
    for option in aws_acm_certificate.app.domain_validation_options : option.domain_name => option
  }

  zone_id = data.cloudflare_zone.main.zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 300
  proxied = false
}

resource "aws_acm_certificate_validation" "app" {
  region                  = aws_acm_certificate.app.region
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.cert_validation : record.name]
}

# CachingOptimized honors the Cache-Control the deploy job sets: a year for
# hashed assets, revalidation for everything else.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "dashboard" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name} dashboard"
  aliases             = [local.app_domain]
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "dashboard"
    domain_name              = aws_s3_bucket.dashboard.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.dashboard.id
  }

  default_cache_behavior {
    target_origin_id       = "dashboard"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # Deep links have no object in the bucket. Without s3:ListBucket, S3 answers
  # a missing key with 403 rather than 404, so both go to the SPA's router.
  dynamic "custom_error_response" {
    for_each = [403, 404]

    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = "/index.html"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.app.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = local.app_domain
  type    = "CNAME"
  content = aws_cloudfront_distribution.dashboard.domain_name
  ttl     = 300
  # CloudFront already terminates TLS with the ACM certificate; a second proxy
  # in front would only add a hop and hide CloudFront's caching behavior.
  proxied = false
}
