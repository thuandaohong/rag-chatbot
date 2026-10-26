# ============================================================
# moved.tf — báo Terraform resource chỉ ĐỔI ĐỊA CHỈ (vào module), không tạo lại.
# Thay cho `terraform state mv`: khai báo trong code, plan xem trước được, review được.
# Sau khi apply thành công có thể xóa các block này.
# ============================================================

# ---- Day 28: module storage ----
moved {
  from = aws_s3_bucket.docs
  to   = module.storage.aws_s3_bucket.docs
}
moved {
  from = aws_s3_bucket_public_access_block.docs
  to   = module.storage.aws_s3_bucket_public_access_block.docs
}
moved {
  from = aws_s3_bucket.web
  to   = module.storage.aws_s3_bucket.web
}
moved {
  from = aws_s3_bucket_public_access_block.web
  to   = module.storage.aws_s3_bucket_public_access_block.web
}

# ---- Day 28: module knowledge_base ----
moved {
  from = aws_bedrockagent_knowledge_base.main
  to   = module.knowledge_base.aws_bedrockagent_knowledge_base.main
}
moved {
  from = aws_bedrockagent_data_source.docs
  to   = module.knowledge_base.aws_bedrockagent_data_source.docs
}
moved {
  from = aws_iam_role.kb
  to   = module.knowledge_base.aws_iam_role.kb
}
moved {
  from = aws_iam_policy.kb_s3
  to   = module.knowledge_base.aws_iam_policy.kb_s3
}
moved {
  from = aws_iam_policy.kb_logs
  to   = module.knowledge_base.aws_iam_policy.kb_logs
}
moved {
  from = aws_iam_role_policy_attachment.kb_s3
  to   = module.knowledge_base.aws_iam_role_policy_attachment.kb_s3
}
moved {
  from = aws_iam_role_policy_attachment.kb_logs
  to   = module.knowledge_base.aws_iam_role_policy_attachment.kb_logs
}

# ---- Day 28: module backend ----
moved {
  from = aws_iam_role.lambda
  to   = module.backend.aws_iam_role.lambda
}
moved {
  from = aws_iam_role_policy_attachment.lambda_logs
  to   = module.backend.aws_iam_role_policy_attachment.lambda_logs
}
moved {
  from = aws_iam_role_policy.bedrock
  to   = module.backend.aws_iam_role_policy.bedrock
}
moved {
  from = aws_lambda_function.api
  to   = module.backend.aws_lambda_function.api
}
moved {
  from = aws_apigatewayv2_api.http
  to   = module.backend.aws_apigatewayv2_api.http
}
moved {
  from = aws_apigatewayv2_integration.lambda
  to   = module.backend.aws_apigatewayv2_integration.lambda
}
moved {
  from = aws_apigatewayv2_route.chat
  to   = module.backend.aws_apigatewayv2_route.chat
}
moved {
  from = aws_apigatewayv2_stage.default
  to   = module.backend.aws_apigatewayv2_stage.default
}
moved {
  from = aws_lambda_permission.api_gw
  to   = module.backend.aws_lambda_permission.api_gw
}

# ---- Day 28: module frontend ----
moved {
  from = aws_cloudfront_origin_access_control.web
  to   = module.frontend.aws_cloudfront_origin_access_control.web
}
moved {
  from = aws_cloudfront_distribution.web
  to   = module.frontend.aws_cloudfront_distribution.web
}
moved {
  from = aws_s3_bucket_policy.web
  to   = module.frontend.aws_s3_bucket_policy.web
}
