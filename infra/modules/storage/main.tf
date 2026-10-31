# ============================================================
# modules/storage — 2 bucket S3 của project (tài liệu + web)
# ============================================================

# ---- Bucket TÀI LIỆU (private, chứa PDF nguồn cho Knowledge Base) ----
resource "aws_s3_bucket" "docs" {
  bucket = var.docs_bucket_name

  tags = {
    Project = "rag-chatbot"
  }
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- Bucket WEB (chứa React build, serve qua CloudFront) ----
resource "aws_s3_bucket" "web" {
  bucket = var.web_bucket_name

  tags = {
    Project = "rag-chatbot"
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
