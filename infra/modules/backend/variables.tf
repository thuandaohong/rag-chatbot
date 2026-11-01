variable "project" {
  description = "Tiền tố tên tài nguyên"
  type        = string
}

variable "model_id" {
  description = "Model trả lời (Bedrock)"
  type        = string
}

variable "kb_id" {
  description = "Knowledge Base ID (từ module knowledge_base) -> env KB_ID của Lambda"
  type        = string
}

variable "kb_arn" {
  description = "Knowledge Base ARN — khóa quyền bedrock:Retrieve của Lambda"
  type        = string
}

variable "handler_source_file" {
  description = "Đường dẫn tới handler.py (tính từ root, vì path.module trong module là modules/backend)"
  type        = string
}

variable "build_dir" {
  description = "Thư mục chứa file zip build ra"
  type        = string
}

variable "guardrail_id" {
  description = "Bedrock Guardrail ID (module guardrail) -> env GUARDRAIL_ID"
  type        = string
}

variable "guardrail_version" {
  description = "Version cố định của guardrail -> env GUARDRAIL_VERSION"
  type        = string
}

variable "guardrail_arn" {
  description = "ARN guardrail — khóa quyền bedrock:ApplyGuardrail"
  type        = string
}

variable "guardrail_profile_arns" {
  description = "ARN cross-region guardrail profile ở mọi destination region (tier Standard cần)"
  type        = list(string)
}

variable "log_retention_days" {
  description = "Số ngày giữ log Lambda trên CloudWatch (giá trị hợp lệ: 1, 3, 5, 7, 14, 30, 60, 90...)"
  type        = number
  default     = 30
}
