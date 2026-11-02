output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "metric_namespace" {
  value = var.metric_namespace # Day 41: alarm đọc CostUsd / GuardrailBlocked trong namespace này
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.api_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.latency_p95.alarm_name,
    aws_cloudwatch_metric_alarm.cost_hourly.alarm_name,
    aws_cloudwatch_metric_alarm.guardrail_spike.alarm_name,
  ]
}
