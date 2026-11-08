# ============================================================
# variables.tf — biến đầu vào, giá trị thật để ở terraform.tfvars
# ============================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "model_id" {
  description = "Model trả lời (Bedrock)"
  type        = string
  default     = "amazon.nova-lite-v1:0"
}

variable "project" {
  description = "Tiền tố tên tài nguyên"
  type        = string
  default     = "rag-chatbot"
}

variable "alert_email" {
  description = "Email nhận alarm. Truyền qua env TF_VAR_alert_email (CI: secret ALERT_EMAIL) — không commit vào tfvars vì repo public"
  type        = string
  sensitive   = true

  # Thiếu secret ALERT_EMAIL -> chuỗi rỗng -> SNS subscription tạo lỗi giữa chừng lúc apply (Day 41).
  # Validate để plan báo lỗi ngay, rõ nguyên nhân.
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email phải là email hợp lệ — kiểm tra GitHub secret ALERT_EMAIL / TF_VAR_alert_email."
  }
}
