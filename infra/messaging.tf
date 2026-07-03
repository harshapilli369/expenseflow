# -----------------------------------------------------------------------------
# SQS — decouples receipt upload from Textract processing; DLQ for poison msgs
# -----------------------------------------------------------------------------
resource "aws_sqs_queue" "processing_dlq" {
  name                      = "${local.prefix}-processing-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "processing" {
  name                       = "${local.prefix}-processing"
  visibility_timeout_seconds = 90 # >= processing Lambda timeout
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })
}

# Allow S3 to send ObjectCreated events to the queue
resource "aws_sqs_queue_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.processing.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_s3_bucket.receipts.arn } }
    }]
  })
}

resource "aws_s3_bucket_notification" "receipts" {
  bucket = aws_s3_bucket.receipts.id
  queue {
    queue_arn     = aws_sqs_queue.processing.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "receipts/"
  }
  depends_on = [aws_sqs_queue_policy.processing]
}

# -----------------------------------------------------------------------------
# SNS — notifications (approval requests / outcomes)
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "notifications" {
  name = "${local.prefix}-notifications"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# EventBridge — monthly rollup schedule (1st of month, 02:00 UTC)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "monthly_rollup" {
  name                = "${local.prefix}-monthly-rollup"
  schedule_expression = "cron(0 2 1 * ? *)"
}

resource "aws_cloudwatch_event_target" "monthly_rollup" {
  rule = aws_cloudwatch_event_rule.monthly_rollup.name
  arn  = aws_lambda_function.fn["monthly_rollup"].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["monthly_rollup"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_rollup.arn
}
