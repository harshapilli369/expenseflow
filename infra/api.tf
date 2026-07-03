# -----------------------------------------------------------------------------
# API Gateway (REST) — single hardened entry point
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name = "${local.prefix}-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# --- Custom TOKEN authorizer (lab stand-in for Cognito) ----------------------
resource "aws_api_gateway_authorizer" "token" {
  name                   = "${local.prefix}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "TOKEN"
  identity_source        = "method.request.header.Authorization"
  authorizer_uri         = aws_lambda_function.fn["authorizer"].invoke_arn
  authorizer_result_ttl_in_seconds = 300
}

resource "aws_lambda_permission" "authorizer_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["authorizer"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/authorizers/${aws_api_gateway_authorizer.token.id}"
}

# --- Resources ---------------------------------------------------------------
resource "aws_api_gateway_resource" "expenses" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "expenses"
}

resource "aws_api_gateway_resource" "pending" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.expenses.id
  path_part   = "pending"
}

resource "aws_api_gateway_resource" "expense_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.expenses.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "decision" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.expense_id.id
  path_part   = "decision"
}

# --- Route definitions (method + AWS_PROXY integration) ----------------------
locals {
  routes = {
    submit         = { resource_id = aws_api_gateway_resource.expenses.id, http = "POST", fn = "submit_expense" }
    query_own      = { resource_id = aws_api_gateway_resource.expenses.id, http = "GET", fn = "query_expenses" }
    query_pending  = { resource_id = aws_api_gateway_resource.pending.id, http = "GET", fn = "query_expenses" }
    approve        = { resource_id = aws_api_gateway_resource.decision.id, http = "POST", fn = "approve_expense" }
  }
}

resource "aws_api_gateway_method" "m" {
  for_each      = local.routes
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value.resource_id
  http_method   = each.value.http
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.token.id
}

resource "aws_api_gateway_integration" "i" {
  for_each                = local.routes
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.m[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.fn[each.value.fn].invoke_arn
}

# Permit API Gateway to invoke each backing function (dedup by function)
locals {
  api_functions = toset([for r in local.routes : r.fn])
}

resource "aws_lambda_permission" "api_invoke" {
  for_each      = local.api_functions
  statement_id  = "AllowAPIGatewayInvoke-${each.value}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn[each.value].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# --- Deployment + stage ------------------------------------------------------
resource "aws_api_gateway_deployment" "dep" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_method.m,
      aws_api_gateway_integration.i,
      aws_api_gateway_authorizer.token.id,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_api_gateway_integration.i]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id           = aws_api_gateway_rest_api.api.id
  deployment_id         = aws_api_gateway_deployment.dep.id
  stage_name            = var.environment
  xray_tracing_enabled  = true
}

# Throttling (protects backend; matches scalability NFR)
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"
  settings {
    throttling_rate_limit  = 500
    throttling_burst_limit = 1000
    metrics_enabled        = true
  }
}
