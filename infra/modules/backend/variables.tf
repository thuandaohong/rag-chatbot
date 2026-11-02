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

variable "pricing" {
  description = <<-EOT
    Bảng giá USD để Lambda tính cost mỗi request (Day 39) -> env PRICING_JSON.
    Nguồn (us-east-1, kiểm tra 2026-11): Nova Lite từ AWS Price List API
    (`aws pricing get-products --service-code AmazonBedrock`), Retrieve + Guardrails
    từ https://aws.amazon.com/bedrock/pricing/ (Standard tier cùng giá Classic).
    Đổi model / giá đổi -> sửa ở đây, không sửa code.
  EOT
  type        = map(number)
  default = {
    llm_input_per_1m_tokens        = 0.06 # Nova Lite input
    llm_output_per_1m_tokens       = 0.24 # Nova Lite output
    retrieve_per_1k_calls          = 1.00 # Retrieve API, KB loại MANAGED
    guardrail_content_per_1k_units = 0.15
    guardrail_topic_per_1k_units   = 0.15
    guardrail_pii_per_1k_units     = 0.10
  }
}
