output "api_base_url" {
  description = "Invoke URL for the deployed stage"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "dynamodb_table" {
  value = aws_dynamodb_table.expenses.name
}

output "receipts_bucket" {
  value = aws_s3_bucket.receipts.bucket
}

output "reports_bucket" {
  value = aws_s3_bucket.reports.bucket
}

output "notifications_topic_arn" {
  value = aws_sns_topic.notifications.arn
}

output "processing_queue_url" {
  value = aws_sqs_queue.processing.url
}

output "dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
