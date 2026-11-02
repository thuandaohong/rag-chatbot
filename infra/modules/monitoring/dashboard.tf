# ============================================================
# modules/monitoring/dashboard.tf — CloudWatch dashboard (lưới 24 cột)
#
#   Hàng 0 : 5 con số tổng (singleValue)
#   Hàng 1 : request & lỗi | latency
#   Hàng 2 : chi phí theo giờ | guardrail chặn theo giờ
#   Hàng 3 : (Logs Insights) cost theo thành phần | latency từng bước
#   Hàng 4 : (Logs Insights) guardrail | lỗi gần nhất
# ============================================================

locals {
  lambda = ["AWS/Lambda", "FunctionName", var.function_name]
  api    = ["AWS/ApiGateway", "ApiId", var.api_id]
  ns     = var.metric_namespace
  src    = "SOURCE '${var.log_group_name}'" # nguồn cho widget Logs Insights

}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ---------------- Hàng 0: con số tổng trong khoảng thời gian đang xem ----------------
      {
        type = "metric", x = 0, y = 0, width = 5, height = 4
        properties = {
          title   = "Requests", region = var.region, view = "singleValue", stat = "Sum", period = 86400
          metrics = [[local.api[0], "Count", local.api[1], local.api[2]]]
        }
      },
      {
        type = "metric", x = 5, y = 0, width = 5, height = 4
        properties = {
          title   = "Chi phí (USD)", region = var.region, view = "singleValue", stat = "Sum", period = 86400
          metrics = [[local.ns, "CostUsd"]]
        }
      },
      {
        type = "metric", x = 10, y = 0, width = 5, height = 4
        properties = {
          title   = "Latency p95 (ms)", region = var.region, view = "singleValue", stat = "p95", period = 86400
          metrics = [[local.api[0], "Latency", local.api[1], local.api[2]]]
        }
      },
      {
        type = "metric", x = 15, y = 0, width = 5, height = 4
        properties = {
          title   = "Guardrail chặn", region = var.region, view = "singleValue", stat = "Sum", period = 86400
          metrics = [[local.ns, "GuardrailBlocked"]]
        }
      },
      {
        type = "metric", x = 20, y = 0, width = 4, height = 4
        properties = {
          title   = "Lỗi 5xx", region = var.region, view = "singleValue", stat = "Sum", period = 86400
          metrics = [[local.api[0], "5xx", local.api[1], local.api[2]]]
        }
      },

      # ---------------- Hàng 1: lưu lượng & latency theo thời gian ----------------
      {
        type = "metric", x = 0, y = 4, width = 12, height = 6
        properties = {
          title = "API: requests, 4xx, 5xx", region = var.region, view = "timeSeries", stat = "Sum", period = 300
          metrics = [
            [local.api[0], "Count", local.api[1], local.api[2], { label = "Requests" }],
            [local.api[0], "4xx", local.api[1], local.api[2], { label = "4xx (input sai)" }],
            [local.api[0], "5xx", local.api[1], local.api[2], { label = "5xx (lỗi server)", color = "#d62728" }],
            [local.lambda[0], "Throttles", local.lambda[1], local.lambda[2], { label = "Lambda throttles" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 4, width = 12, height = 6
        properties = {
          title = "Latency (ms)", region = var.region, view = "timeSeries", period = 300
          metrics = [
            [local.api[0], "Latency", local.api[1], local.api[2], { stat = "p95", label = "API p95 (người dùng chờ)" }],
            [local.api[0], "Latency", local.api[1], local.api[2], { stat = "Average", label = "API trung bình" }],
            [local.lambda[0], "Duration", local.lambda[1], local.lambda[2], { stat = "Average", label = "Lambda trung bình" }],
          ]
        }
      },

      # ---------------- Hàng 2: chi phí & guardrail (custom metric) ----------------
      {
        type = "metric", x = 0, y = 10, width = 12, height = 6
        properties = {
          title   = "Chi phí theo giờ (USD)", region = var.region, view = "timeSeries", stat = "Sum", period = 3600
          metrics = [[local.ns, "CostUsd", { label = "USD / giờ" }]]
        }
      },
      {
        type = "metric", x = 12, y = 10, width = 12, height = 6
        properties = {
          title   = "Guardrail chặn theo giờ", region = var.region, view = "timeSeries", stat = "Sum", period = 3600
          metrics = [[local.ns, "GuardrailBlocked", { label = "Lần chặn / giờ", color = "#ff7f0e" }]]
        }
      },

      # ---------------- Hàng 3-4: Logs Insights (phân tích sâu, không tạo metric) ----------------
      {
        type = "log", x = 0, y = 16, width = 12, height = 6
        properties = {
          title  = "Chi phí theo thành phần (model chỉ ~7%)"
          region = var.region
          view   = "table"
          query  = "${local.src} | filter type = \"rag_request\" and status = 200 | stats sum(cost_usd.retrieve) as retrieve_usd, sum(cost_usd.guardrail) as guardrail_usd, sum(cost_usd.llm) as llm_usd, sum(cost_usd.total) as total_usd, sum(cost_usd.llm) / sum(cost_usd.total) * 100 as llm_pct"
        }
      },
      {
        type = "log", x = 12, y = 16, width = 12, height = 6
        properties = {
          title  = "Latency trung bình từng bước (ms)"
          region = var.region
          view   = "table"
          query  = "${local.src} | filter type = \"rag_request\" and status = 200 and ispresent(stage_ms.generate) | stats avg(stage_ms.guardrail_in) as guardrail_in, avg(stage_ms.retrieve) as retrieve, avg(stage_ms.generate) as generate, avg(stage_ms.guardrail_out) as guardrail_out, avg(latency_ms) as total"
        }
      },
      {
        type = "log", x = 0, y = 22, width = 12, height = 6
        properties = {
          title  = "Guardrail: kết quả 2 chiều"
          region = var.region
          view   = "table"
          query  = "${local.src} | filter type = \"rag_request\" and status = 200 | stats count(*) as requests by guardrail_input, guardrail_output | sort requests desc"
        }
      },
      {
        type = "log", x = 12, y = 22, width = 12, height = 6
        properties = {
          title  = "Lỗi gần nhất (status >= 400)"
          region = var.region
          view   = "table"
          query  = "${local.src} | filter type = \"rag_request\" and status >= 400 | fields @timestamp, status, error, latency_ms, request_id | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
