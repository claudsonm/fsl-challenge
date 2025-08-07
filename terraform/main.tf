# terraform workspace new devel
# terraform workspace new stage
# terraform workspace new prod
# terraform workspace select devel
# terraform init
# terraform apply -var-file=environments/devel.tfvars

terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "6.7.0"
        }
        random = {
            source = "hashicorp/random"
            version = "3.7.2"
        }
    }

    backend "s3" {
        bucket = "fsl-challenge-223"
        key = "devops-challenge/terraform.tfstate"
        region = "us-east-1"
        use_lockfile = true
    }
}

provider "aws" {
    region = "us-east-1"
    # profile = "fsl-challenge"
    default_tags {
        tags = {
            Environment = var.environment
            Project = var.project
            Owner = "team-fsl"
        }
    }
}

locals {
    s3_origin_id = var.project
}

resource "random_string" "bucket_suffix" {
    length      = 4
    special = false
    upper = false
}

resource "random_string" "logs_bucket_suffix" {
    length      = 4
    special = false
    upper = false
}

resource "aws_s3_bucket" "fsl_challenge" {
    bucket = "fsl-challenge-${var.environment}-${random_string.bucket_suffix.id}"
}

resource "aws_s3_bucket_policy" "allow_access_from_cdn" {
    bucket = aws_s3_bucket.fsl_challenge.id
    policy = data.aws_iam_policy_document.allow_access_from_cdn.json
}

data "aws_iam_policy_document" "allow_access_from_cdn" {
    statement {
        principals {
            type        = "Service"
            identifiers = ["cloudfront.amazonaws.com"]
        }

        actions = [
            "s3:GetObject",
        ]

        resources = [
            "${aws_s3_bucket.fsl_challenge.arn}/*",
        ]

        condition {
            test     = "StringEquals"
            values = [aws_cloudfront_distribution.s3_distribution.arn]
            variable = "AWS:SourceArn"
        }
    }
}



resource "aws_s3_bucket" "fsl_challenge_logs" {
    bucket = "fsl-challenge-${var.environment}-logs-${random_string.logs_bucket_suffix.id}"
}

resource "aws_s3_bucket_ownership_controls" "fsl_challenge_logs" {
    bucket = aws_s3_bucket.fsl_challenge_logs.id

    rule {
        object_ownership = "BucketOwnerPreferred"
    }
}

resource "aws_s3_bucket_acl" "fsl_challenge_logs" {
    depends_on = [aws_s3_bucket_ownership_controls.fsl_challenge_logs]

    bucket = aws_s3_bucket.fsl_challenge_logs.id
    acl    = "log-delivery-write"
}

resource "aws_cloudfront_origin_access_control" "default" {
    name                              = "cf-origin-access-control"
    description                       = "cf-origin-access-control"
    origin_access_control_origin_type = "s3"
    signing_behavior                  = "always"
    signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
    depends_on = [aws_s3_bucket_acl.fsl_challenge_logs]

    origin {
        domain_name              = aws_s3_bucket.fsl_challenge.bucket_regional_domain_name
        origin_access_control_id = aws_cloudfront_origin_access_control.default.id
        origin_id                = local.s3_origin_id
    }

    enabled             = true
    is_ipv6_enabled     = true
    default_root_object = "index.html"

    logging_config {
        include_cookies = false
        bucket          = aws_s3_bucket.fsl_challenge_logs.bucket_regional_domain_name
        # prefix          = "myprefix"
    }

    # aliases = ["mysite.example.com", "yoursite.example.com"]

    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id

        forwarded_values {
            query_string = false

            cookies {
                forward = "none"
            }
        }

        viewer_protocol_policy = "allow-all"
        min_ttl                = 0
        default_ttl            = 3600
        max_ttl                = 86400
    }

    price_class = "PriceClass_All"

    restrictions {
        geo_restriction {
            restriction_type = "none"
            locations        = []
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }
}

output "cdn_url" {
    value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "cdn_distribution_id" {
    value = aws_cloudfront_distribution.s3_distribution.id
}

output "app_s3_bucket_name" {
    value = aws_s3_bucket.fsl_challenge.bucket
}

