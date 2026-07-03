locals {
  # Per-function packaging + sizing. All use the shared LabRole in the lab.
  functions = {
    submit_expense  = { timeout = 15, memory = 256 }
    query_expenses  = { timeout = 15, memory = 256 }
    approve_expense = { timeout = 15, memory = 256 }
    process_receipt = { timeout = 60, memory = 512 }
    monthly_rollup  = { timeout = 120, memory = 512 }
    authorizer      = { timeout = 10, memory = 128 }
  }

  lambda_env = {
    TABLE_NAME              = aws_dynamodb_table.expenses.name
    RECEIPTS_BUCKET         = aws_s3_bucket.receipts.bucket
    REPORTS_BUCKET          = aws_s3_bucket.reports.bucket
    NOTIFICATIONS_TOPIC_ARN = aws_sns_topic.notifications.arn
    POLICY_THRESHOLD        = var.policy_threshold
  }
}

data "archive_file" "fn" {
  for_each    = local.functions
  type        = "zip"
  source_dir  = "${path.module}/../src/${each.key}"
  output_path = "${path.module}/build/${each.key}.zip"
}

resource "aws_lambda_function" "fn" {
  for_each         = local.functions
  function_name    = "${local.prefix}-${replace(each.key, "_", "-")}"
  role             = var.lab_role_arn
  runtime          = "python3.12"
  architectures    = ["arm64"] # Graviton: better price/perf and efficiency
  handler          = "handler.handler"
  filename         = data.archive_file.fn[each.key].output_path
  source_code_hash = data.archive_file.fn[each.key].output_base64sha256
  timeout          = each.value.timeout
  memory_size      = each.value.memory

  environment {
    variables = local.lambda_env
  }

  tracing_config {
    mode = "Active" # AWS X-Ray distributed tracing
  }
}

# CloudWatch log groups with retention (operational excellence + cost)
resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.functions
  name              = "/aws/lambda/${local.prefix}-${replace(each.key, "_", "-")}"
  retention_in_days = var.log_retention_days
}

# SQS -> ProcessReceipt event source mapping
resource "aws_lambda_event_source_mapping" "process_receipt" {
  event_source_arn                   = aws_sqs_queue.processing.arn
  function_name                      = aws_lambda_function.fn["process_receipt"].arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}
