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
