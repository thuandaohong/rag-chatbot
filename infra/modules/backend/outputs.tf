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
