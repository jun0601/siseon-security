terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# AWS Budgets - 일별 $5 초과 알람
resource "aws_budgets_budget" "daily" {
  name         = "${var.project_name}-budget-daily"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "DAILY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.billing.arn]
  }
}

# AWS Budgets - 월별 $60 초과 알람
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-budget-monthly"
  budget_type  = "COST"
  limit_amount = "60"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.billing.arn]
  }
}

# SNS 토픽
resource "aws_sns_topic" "billing" {
  name = "${var.project_name}-billing-alert"
}

# SNS → Lambda 구독
resource "aws_sns_topic_subscription" "billing" {
  topic_arn = aws_sns_topic.billing.arn
  protocol  = "lambda"
  endpoint  = var.lambda_billing_arn
}

# Lambda 트리거 권한
resource "aws_lambda_permission" "billing_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_billing_arn
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.billing.arn
}