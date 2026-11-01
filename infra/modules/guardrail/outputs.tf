output "guardrail_id" {
  value = aws_bedrock_guardrail.main.guardrail_id
}

output "guardrail_arn" {
  value = aws_bedrock_guardrail.main.guardrail_arn
}

output "guardrail_version" {
  value = aws_bedrock_guardrail_version.main.version # app gọi version này, không gọi DRAFT
}

# Day 36: Lambda cần bedrock:ApplyGuardrail trên guardrail + profile ở MỌI destination region
output "guardrail_profile_arns" {
  value = [
    for r in ["us-east-1", "us-east-2", "us-west-2"] :
    "arn:aws:bedrock:${r}:${data.aws_caller_identity.current.account_id}:guardrail-profile/${var.guardrail_profile_id}"
  ]
}
