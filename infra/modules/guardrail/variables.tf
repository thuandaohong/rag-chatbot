variable "project" {
  description = "Tiền tố tên tài nguyên"
  type        = string
}

variable "guardrail_profile_id" {
  description = "Cross-region guardrail profile (bắt buộc cho tier Standard). Source us-east-1 -> us.guardrail.v1:0"
  type        = string
  default     = "us.guardrail.v1:0"
}
