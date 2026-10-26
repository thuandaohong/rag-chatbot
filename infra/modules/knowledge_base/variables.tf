variable "project" {
  description = "Tiền tố tên tài nguyên"
  type        = string
}

variable "docs_bucket_name" {
  description = "Bucket chứa PDF nguồn (từ module storage)"
  type        = string
}

variable "docs_bucket_arn" {
  description = "ARN bucket PDF — data source đọc + role KB được cấp quyền"
  type        = string
}
