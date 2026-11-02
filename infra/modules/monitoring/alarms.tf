# ============================================================
# modules/monitoring/alarms.tf — Alarm + SNS (Day 41)
#
#   Metric vượt ngưỡng -> Alarm (trạng thái ALARM) -> SNS topic -> email
#
# 4 alarm, 4 trục: độ tin cậy (5xx), trải nghiệm (latency), tiền (cost), an toàn (guardrail).
# Free tier: 10 alarm metric -> 4 alarm miễn phí.
# ============================================================

# ---- SNS: kênh trung gian. Alarm bắn vào topic, topic phát cho mọi subscriber ----
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# Sau apply AWS gửi email "Subscription Confirmation" -> PHẢI bấm link mới nhận được cảnh báo
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  t             = var.alarm_thresholds
}

# ---- 1) Độ tin cậy: lỗi 5xx ở API Gateway ----
# Dùng API 5xx thay vì Lambda Errors: handler bắt ClientError rồi TRẢ 502 (không crash)
# -> Lambda Errors không đếm. API 5xx đếm cả 502 đó + Lambda crash + timeout 30s.
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project}-api-5xx"
  alarm_description   = "API trả >= ${local.t.api_5xx_per_5min} lỗi 5xx trong 5 phút (Bedrock lỗi quyền/quota, Lambda crash, timeout)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = local.t.api_5xx_per_5min
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching" # không có request = bình thường, không báo động
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions # báo cả khi đã hết lỗi
}

# ---- 2) Trải nghiệm: latency p95 ----
# p95 (không phải Average): trung bình đẹp vẫn có thể che 5% người dùng chờ rất lâu.
# 2 cửa sổ liên tiếp: 1 spike (vd cold start) không gây báo giả.
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.project}-latency-p95"
  alarm_description   = "p95 latency API > ${local.t.latency_p95_ms}ms trong 10 phút liên tiếp"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = var.api_id }
  extended_statistic  = "p95" # percentile dùng extended_statistic, không phải statistic
  period              = 300
  evaluation_periods  = 2
  threshold           = local.t.latency_p95_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---- 3) Tiền: chi phí theo giờ (custom metric CostUsd, Day 40) ----
# Bắt "đốt tiền" theo giờ (bot spam, vòng lặp gọi API) — sớm hơn nhiều so với
# AWS Budget (tính theo ngày, trễ vài giờ). Budget vẫn giữ để bắt chi phí cố định.
resource "aws_cloudwatch_metric_alarm" "cost_hourly" {
  alarm_name          = "${var.project}-cost-hourly"
  alarm_description   = "Chi phí request > ${local.t.cost_usd_per_hour} USD/giờ (bình thường ~0.002 USD/request)"
  namespace           = var.metric_namespace
  metric_name         = "CostUsd"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = local.t.cost_usd_per_hour
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# ---- 4) An toàn: guardrail chặn nhiều bất thường (custom metric GuardrailBlocked) ----
# Vài lần chặn là bình thường; dồn dập = có người dò jailbreak / spam nội dung độc.
resource "aws_cloudwatch_metric_alarm" "guardrail_spike" {
  alarm_name          = "${var.project}-guardrail-spike"
  alarm_description   = "Guardrail chặn >= ${local.t.guardrail_blocks_per_15m} lần trong 15 phút (dò jailbreak / spam?)"
  namespace           = var.metric_namespace
  metric_name         = "GuardrailBlocked"
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = local.t.guardrail_blocks_per_15m
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}
