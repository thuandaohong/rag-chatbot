variable "project" {
  description = "Tiền tố tên tài nguyên"
  type        = string
}

variable "web_bucket_id" {
  description = "Bucket web (từ module storage) — gắn bucket policy"
  type        = string
}

variable "web_bucket_arn" {
  description = "ARN bucket web — resource trong bucket policy"
  type        = string
}

variable "web_bucket_regional_domain_name" {
  description = "Domain regional của bucket web — origin của CloudFront"
  type        = string
}
