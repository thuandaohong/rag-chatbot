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

variable "alert_email" {
  description = "Email nhận cảnh báo. KHÔNG để trong terraform.tfvars (repo public) -> truyền qua TF_VAR_alert_email (GitHub secret ALERT_EMAIL / export ở máy)"
  type        = string
  sensitive   = true
}

variable "alarm_thresholds" {
  description = "Ngưỡng alarm — chỉnh ở đây, không sửa từng alarm"
  type = object({
    api_5xx_per_5min         = number # số lỗi 5xx trong 5 phút
    latency_p95_ms           = number # p95 latency API (ms), 2 cửa sổ 5 phút liên tiếp
    cost_usd_per_hour        = number # chi phí/giờ; bình thường ~$0.002/request
    guardrail_blocks_per_15m = number # số lần chặn/15 phút; cao bất thường = có người tấn công
  })
  default = {
    api_5xx_per_5min         = 3
    latency_p95_ms           = 10000
    cost_usd_per_hour        = 0.5 # ~250 request/giờ — gấp nhiều lần traffic học tập
    guardrail_blocks_per_15m = 10
  }
}
