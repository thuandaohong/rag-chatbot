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
