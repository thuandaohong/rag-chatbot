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

  environment {
    variables = {
      KB_ID    = var.kb_id
      MODEL_ID = var.model_id
    }
  }
}
