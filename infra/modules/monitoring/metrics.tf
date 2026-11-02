# ============================================================
# modules/monitoring/metrics.tf — rút metric từ structured log (Day 37-39)
#
# Mỗi custom metric $0.30/tháng (free tier: 10 metric). Chỉ tạo metric cho thứ AWS KHÔNG
# có sẵn VÀ cần theo dõi liên tục / đặt alarm (Day 41):
#   - CostUsd           : rút GIÁ TRỊ  (value = "$.cost_usd.total")
#   - GuardrailBlocked  : ĐẾM sự kiện  (value = "1")
# Request/lỗi/latency đã có metric AWS miễn phí (AWS/ApiGateway, AWS/Lambda) -> không tạo lại.
# Phân tích sâu (cost theo thành phần, latency từng bước...) dùng widget Logs Insights.
# ============================================================

resource "aws_cloudwatch_log_metric_filter" "cost" {
  name           = "${var.project}-cost-usd"
  log_group_name = var.log_group_name
  pattern        = "{ $.type = \"rag_request\" && $.status = 200 && $.cost_usd.total > 0 }"

  metric_transformation {
    name      = "CostUsd"
    namespace = var.metric_namespace
    value     = "$.cost_usd.total" # field lồng: cost_usd -> total
    unit      = "None"             # CloudWatch không có đơn vị tiền tệ
  }
}

resource "aws_cloudwatch_log_metric_filter" "guardrail_blocked" {
  name           = "${var.project}-guardrail-blocked"
  log_group_name = var.log_group_name
  # Bị chặn ở 1 trong 2 chiều (Day 36 log guardrail_input/guardrail_output riêng)
  pattern = "{ $.type = \"rag_request\" && ($.guardrail_input = \"BLOCKED\" || $.guardrail_output = \"BLOCKED\") }"

  metric_transformation {
    name      = "GuardrailBlocked"
    namespace = var.metric_namespace
    value     = "1" # mỗi dòng khớp đếm 1
    unit      = "Count"
  }
}
