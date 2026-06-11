terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# EventBridge 스케줄 (매일 KST 09:00)
resource "aws_cloudwatch_event_rule" "billing_check" {
  name                = "${var.project_name}-billing-daily-check"
  description         = "매일 KST 09:00 비용 확인"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "billing_check" {
  rule      = aws_cloudwatch_event_rule.billing_check.name
  target_id = "billing-lambda"
  arn       = var.lambda_billing_arn
}

resource "aws_lambda_permission" "billing_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_billing_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.billing_check.arn
}

# AWS Budgets (시각화/참고용으로만 유지)
resource "aws_budgets_budget" "daily" {
  name         = "${var.project_name}-budget-daily"
  budget_type  = "COST"
  limit_amount = "8"
  limit_unit   = "USD"
  time_unit    = "DAILY"
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-budget-monthly"
  budget_type  = "COST"
  limit_amount = "120.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
}