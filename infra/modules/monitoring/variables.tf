variable "project" {
  description = "Tiền tố tên tài nguyên"
  type        = string
}

variable "region" {
  description = "Region của metric (widget dashboard cần ghi rõ)"
  type        = string
}

variable "log_group_name" {
  description = "Log group của Lambda (module backend) — nguồn của metric filter + widget Logs Insights"
  type        = string
}

variable "function_name" {
  description = "Tên Lambda — dimension cho metric AWS/Lambda"
  type        = string
}

variable "api_id" {
  description = "ID HTTP API — dimension cho metric AWS/ApiGateway"
  type        = string
}

variable "metric_namespace" {
  description = "Namespace của custom metric (tách khỏi metric AWS)"
  type        = string
  default     = "RagChatbot"
}
