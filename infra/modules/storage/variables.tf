variable "docs_bucket_name" {
  description = "Tên bucket chứa PDF nguồn cho Knowledge Base"
  type        = string
}

variable "web_bucket_name" {
  description = "Tên bucket chứa React build (origin của CloudFront)"
  type        = string
}
