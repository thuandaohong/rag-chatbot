# ============================================================
# modules/backend/logging.tf — Log group của Lambda + câu query Logs Insights lưu sẵn (Day 37)
#
# handler.py ghi mỗi request 1 dòng JSON {"type": "rag_request", ...}. Logs Insights tự
# tách field JSON -> filter/stats thẳng trên latency_ms, status, guardrail_input...
# ============================================================

# Log group do Lambda tự tạo lúc chạy lần đầu (retention = vĩnh viễn) -> import vào TF
# để đặt thời hạn giữ log. Log tính tiền theo dung lượng lưu, giữ mãi = tiền tăng mãi.
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project = var.project
  }
}

locals {
  # Câu query lưu sẵn: CloudWatch -> Logs Insights -> Saved queries -> thư mục "rag-chatbot/"
  insights_queries = {
    "overview" = <<-EOT
      filter type = "rag_request"
      | stats count(*) as requests, avg(latency_ms) as avg_ms, pct(latency_ms, 50) as p50_ms, pct(latency_ms, 95) as p95_ms by bin(1h)
    EOT

    "status-errors" = <<-EOT
      filter type = "rag_request"
      | stats count(*) as requests by status, error
      | sort requests desc
    EOT

    "guardrail" = <<-EOT
      filter type = "rag_request" and status = 200
      | stats count(*) as requests by guardrail_input, guardrail_output
      | sort requests desc
    EOT

    "latency-by-stage" = <<-EOT
      filter type = "rag_request" and status = 200 and ispresent(stage_ms.generate)
      | stats avg(stage_ms.guardrail_in) as guardrail_in, avg(stage_ms.retrieve) as retrieve, avg(stage_ms.generate) as generate, avg(stage_ms.guardrail_out) as guardrail_out, avg(latency_ms) as total
    EOT

    "tokens-daily" = <<-EOT
      filter type = "rag_request" and status = 200
      | stats sum(input_tokens) as input_tokens, sum(output_tokens) as output_tokens, count(*) as requests by bin(1d)
    EOT

    "slow-requests" = <<-EOT
      filter type = "rag_request" and latency_ms > 8000
      | fields @timestamp, request_id, latency_ms, stage_ms.retrieve, stage_ms.generate, cold_start
      | sort latency_ms desc
      | limit 20
    EOT
  }
}

resource "aws_cloudwatch_query_definition" "rag" {
  for_each = local.insights_queries

  name            = "${var.project}/${each.key}"
  log_group_names = [aws_cloudwatch_log_group.api.name]
  query_string    = each.value
}
