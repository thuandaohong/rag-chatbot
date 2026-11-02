output "api_url" {
  value = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/chat"
}

output "lambda_function_name" {
  value = aws_lambda_function.api.function_name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.api.arn
}

# Day 40: module monitoring cần để tạo metric filter + vẽ metric API Gateway
output "log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}

output "api_id" {
  value = aws_apigatewayv2_api.http.id
}
