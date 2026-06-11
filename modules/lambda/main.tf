# Lambda 실행 IAM 역할
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda 함수 zip 패키징
data "archive_file" "login_alert" {
  type        = "zip"
  source_file = "${path.module}/functions/login_alert.py"
  output_path = "${path.module}/functions/login_alert.zip"
}

data "archive_file" "delete_alert" {
  type        = "zip"
  source_file = "${path.module}/functions/delete_alert.py"
  output_path = "${path.module}/functions/delete_alert.zip"
}

# Lambda 함수 - 로그인 감지
resource "aws_lambda_function" "login_alert" {
  function_name    = "${var.project_name}-lambda-login-alert"
  role             = aws_iam_role.lambda.arn
  handler          = "login_alert.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.login_alert.output_path
  source_code_hash = data.archive_file.login_alert.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      TEAMS_WEBHOOK_URL = var.teams_webhook_login
    }
  }
}

# Lambda 함수 - 삭제 감지
resource "aws_lambda_function" "delete_alert" {
  function_name    = "${var.project_name}-lambda-delete-alert"
  role             = aws_iam_role.lambda.arn
  handler          = "delete_alert.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.delete_alert.output_path
  source_code_hash = data.archive_file.delete_alert.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      TEAMS_WEBHOOK_URL = var.teams_webhook_delete
    }
  }
}

# CloudWatch Logs → Lambda 트리거 권한
resource "aws_lambda_permission" "login_alert" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login_alert.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${var.log_group_arn}:*"
}

resource "aws_lambda_permission" "delete_alert" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_alert.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${var.log_group_arn}:*"
}

# Subscription Filter - 로그인
resource "aws_cloudwatch_log_subscription_filter" "login" {
  name            = "${var.project_name}-sub-login"
  log_group_name  = var.log_group_name
  filter_pattern  = "{ $.eventName = \"ConsoleLogin\" }"
  destination_arn = aws_lambda_function.login_alert.arn

  depends_on = [aws_lambda_permission.login_alert]
}

# Subscription Filter - 삭제
resource "aws_cloudwatch_log_subscription_filter" "delete" {
  name            = "${var.project_name}-sub-delete"
  log_group_name  = var.log_group_name
  filter_pattern  = "{ ($.eventName = \"Delete*\") || ($.eventName = \"Remove*\") || ($.eventName = \"Terminate*\") }"
  destination_arn = aws_lambda_function.delete_alert.arn

  depends_on = [aws_lambda_permission.delete_alert]
}

# Billing Lambda ZIP
data "archive_file" "billing_alert" {
  type        = "zip"
  source_file = "${path.module}/functions/billing_alert.py"
  output_path = "${path.module}/functions/billing_alert.zip"
}

# Billing Lambda 함수
resource "aws_lambda_function" "billing_alert" {
  function_name    = "${var.project_name}-lambda-billing-alert"
  role             = aws_iam_role.lambda.arn
  handler          = "billing_alert.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.billing_alert.output_path
  source_code_hash = data.archive_file.billing_alert.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      TEAMS_WEBHOOK_URL = var.teams_webhook_billing
    }
  }
}

# S3 → Azure Blob 동기화 Lambda ZIP
data "archive_file" "s3_to_azure" {
  type        = "zip"
  source_file = "${path.module}/functions/s3_to_azure.py"
  output_path = "${path.module}/functions/s3_to_azure.zip"
}

# S3 → Azure Blob 동기화 Lambda
resource "aws_lambda_function" "s3_to_azure" {
  function_name    = "${var.project_name}-lambda-s3-to-azure"
  role             = aws_iam_role.lambda.arn
  handler          = "s3_to_azure.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.s3_to_azure.output_path
  source_code_hash = data.archive_file.s3_to_azure.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      AZURE_CONNECTION_STRING = var.azure_connection_string
      AZURE_CONTAINER_NAME    = "cloudtrail-backup"
      SOURCE_BUCKET           = var.cloudtrail_bucket
      SOURCE_PREFIX           = "AWSLogs/448768137813/CloudTrail/ap-northeast-2/"
    }
  }
}

# 매일 새벽 2시 실행 (EventBridge)
resource "aws_cloudwatch_event_rule" "s3_to_azure_schedule" {
  name                = "${var.project_name}-s3-to-azure-schedule"
  description         = "매일 새벽 2시 S3 → Azure Blob 동기화"
  schedule_expression = "cron(0 1,9,17 * * ? *)"
}

resource "aws_cloudwatch_event_target" "s3_to_azure" {
  rule      = aws_cloudwatch_event_rule.s3_to_azure_schedule.name
  target_id = "s3-to-azure-lambda"
  arn       = aws_lambda_function.s3_to_azure.arn
}

resource "aws_lambda_permission" "s3_to_azure_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_to_azure.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_to_azure_schedule.arn
}

resource "aws_iam_role_policy" "lambda_s3_read" {
  name = "${var.project_name}-lambda-s3-read"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::aws-cloudtrail-logs-448768137813-05d6a32b",
          "arn:aws:s3:::aws-cloudtrail-logs-448768137813-05d6a32b/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ce:GetCostAndUsage"]
        Resource = "*"
      }
    ]
  })
}

