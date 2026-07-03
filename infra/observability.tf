# -----------------------------------------------------------------------------
# Observability — alarms on the signals that matter (report section 8.1/8.3)
# -----------------------------------------------------------------------------

# Any message reaching the DLQ means receipts failed processing repeatedly.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${local.prefix}-dlq-not-empty"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.processing_dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  treat_missing_data  = "notBreaching"
}

# Elevated Lambda errors on the synchronous submit path.
resource "aws_cloudwatch_metric_alarm" "submit_errors" {
  alarm_name          = "${local.prefix}-submit-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.fn["submit_expense"].function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  treat_missing_data  = "notBreaching"
}

# API Gateway 5XX rate.
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.prefix}-api-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions          = { ApiName = aws_api_gateway_rest_api.api.name, Stage = aws_api_gateway_stage.prod.stage_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  treat_missing_data  = "notBreaching"
}

# -----------------------------------------------------------------------------
# Single-pane dashboard across the whole request path (ops excellence, §8.1)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "API Gateway — requests, errors, p95 latency"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.api.name, "Stage", aws_api_gateway_stage.prod.stage_name],
            ["AWS/ApiGateway", "4XXError", "ApiName", aws_api_gateway_rest_api.api.name, "Stage", aws_api_gateway_stage.prod.stage_name],
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.api.name, "Stage", aws_api_gateway_stage.prod.stage_name],
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.api.name, "Stage", aws_api_gateway_stage.prod.stage_name, { stat = "p95" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Lambda — invocations & errors (submit + process_receipt)"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.fn["submit_expense"].function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.fn["submit_expense"].function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.fn["process_receipt"].function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.fn["process_receipt"].function_name]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "SQS — processing queue & DLQ depth"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.processing.name],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.processing_dlq.name]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "DynamoDB — consumed read/write capacity"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.expenses.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.expenses.name]
          ]
        }
      }
    ]
  })
}
