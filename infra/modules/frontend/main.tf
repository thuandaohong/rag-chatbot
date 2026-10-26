# ============================================================
# modules/frontend — CDN + OAC cho frontend (import từ cái đã có)
# ============================================================

locals {
  # origin_id do console sinh ra — giữ nguyên để không phải tạo lại distribution
  web_origin_id = "rag-chatbot-web-thuan-20261012.s3.us-east-1.amazonaws.com-mvm3el4e3ci"
}

# ---- OAC: CloudFront ký request (SigV4) khi đọc S3 -> bucket không cần public ----
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "oac-rag-chatbot-web-thuan-20261012.s3.us-east-1.amaz-mvm3pgg7c37"
  description                       = "Created by CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---- Distribution: phục vụ React build từ bucket web qua HTTPS ----
resource "aws_cloudfront_distribution" "web" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2"
  price_class     = "PriceClass_All"
  # WAF do console tự tạo kèm distribution (quản ngoài Terraform)
  web_acl_id = "arn:aws:wafv2:us-east-1:${data.aws_caller_identity.current.account_id}:global/webacl/CreatedByCloudFront-2e404c4f/95a3a18a-fffa-47b1-beb6-1dc308e01f59"

  tags = {
    Name = "${var.project}-web"
  }

  origin {
    domain_name              = var.web_bucket_regional_domain_name
    origin_id                = local.web_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  default_cache_behavior {
    target_origin_id       = local.web_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed: CachingOptimized
  }

  # SPA: đường dẫn không có file trong S3 (OAC trả 403) -> trả index.html cho React
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 26
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # domain *.cloudfront.net, chưa gắn domain riêng
  }
}

# ---- Bucket policy: cho phép đúng distribution này đọc bucket web ----
data "aws_iam_policy_document" "web_bucket" {
  # TODO: statement public này là tàn dư từ lúc host S3 website — xem ghi chú Day 27.
  # Đang bị vô hiệu bởi public access block (restrict_public_buckets) nhưng nên xóa.
  statement {
    sid       = "PublicReadForWebsite"
    actions   = ["s3:GetObject"]
    resources = ["${var.web_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${var.web_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = var.web_bucket_id
  policy = data.aws_iam_policy_document.web_bucket.json
}
