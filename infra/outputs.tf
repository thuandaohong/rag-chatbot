# ============================================================
# outputs.tf — giá trị cần dùng sau apply (dán vào .env, lệnh deploy...)
# ============================================================

output "api_url" {
  value = module.backend.api_url
}

output "lambda_function_name" {
  value = module.backend.lambda_function_name
}

output "lambda_role_arn" {
  value = module.backend.lambda_role_arn
}

output "knowledge_base_id" {
  value = module.knowledge_base.kb_id
}

output "cloudfront_url" {
  value = module.frontend.cloudfront_url
}

output "cloudfront_distribution_id" {
  value = module.frontend.cloudfront_distribution_id
}

output "guardrail_id" {
  value = module.guardrail.guardrail_id
}

output "guardrail_version" {
  value = module.guardrail.guardrail_version
}
