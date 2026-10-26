# ============================================================
# modules/backend/apigateway.tf — HTTP API đứng trước Lambda
# ============================================================

# 1) API: cổng HTTP, cấu hình CORS ngay tại đây (Lambda không trả header CORS)
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"] # dev; prod siết theo domain CloudFront
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

# 2) Integration: nối API với Lambda (kiểu proxy -> đẩy nguyên request vào Lambda)
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

# 3) Route: POST /chat -> integration ở trên
resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# 4) Stage: $default, auto-deploy (không thêm tên vào URL)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

# 5) Resource-based policy: CHO PHÉP API Gateway này gọi Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
