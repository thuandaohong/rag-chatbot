# ============================================================
# modules/backend/lambda.tf — Hàm Lambda RAG (import từ hàm đã có)
# ============================================================

# Đóng gói handler.py thành zip. boto3 có sẵn trong runtime -> không cần deps.
data "archive_file" "api" {
  type        = "zip"
  source_file = var.handler_source_file
  output_path = "${var.build_dir}/handler.zip"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project}-api"
  role          = aws_iam_role.lambda.arn # role mới từ Day 23
  runtime       = "python3.12"
  handler       = "handler.lambda_handler" # file handler.py, hàm lambda_handler
  timeout       = 30                       # RAG mất 5-10s, để 30s cho chắc
  memory_size   = 256

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256 # đổi code -> TF biết redeploy

  # Code do pipeline deploy-backend đẩy (update-function-code), Terraform chỉ quản cấu hình
  # (env, memory, timeout, role). Không ignore -> 2 bên giành nhau, apply sau đè code của CI.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  environment {
    variables = {
      KB_ID             = var.kb_id
      MODEL_ID          = var.model_id
      GUARDRAIL_ID      = var.guardrail_id # feature flag: thiếu 1 trong 2 -> handler bỏ qua guardrail
      GUARDRAIL_VERSION = var.guardrail_version
      PRICING_JSON      = jsonencode(var.pricing) # handler tính cost_usd mỗi request
    }
  }
}
