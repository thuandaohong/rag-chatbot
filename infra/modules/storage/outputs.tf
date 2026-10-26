# Xuất ra để module/file khác dùng (KB đọc docs, CloudFront đọc web)

output "docs_bucket_name" {
  value = aws_s3_bucket.docs.bucket
}

output "docs_bucket_arn" {
  value = aws_s3_bucket.docs.arn
}

output "web_bucket_id" {
  value = aws_s3_bucket.web.id
}

output "web_bucket_arn" {
  value = aws_s3_bucket.web.arn
}

output "web_bucket_regional_domain_name" {
  value = aws_s3_bucket.web.bucket_regional_domain_name
}
