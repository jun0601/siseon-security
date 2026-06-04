# Metric Filter - 삭제 작업
resource "aws_cloudwatch_log_metric_filter" "delete_action" {
  name           = "${var.project_name}-filter-delete-action"
  log_group_name = var.log_group_name
  pattern        = "{ ($.eventName = \"Delete*\") || ($.eventName = \"Remove*\") || ($.eventName = \"Terminate*\") }"

  metric_transformation {
    name          = "DeleteActionCount"
    namespace     = "SiseonSecurity"
    value         = "1"
    default_value = "0"
  }
}

# Metric Filter - 콘솔 로그인
resource "aws_cloudwatch_log_metric_filter" "console_login" {
  name           = "${var.project_name}-filter-console-login"
  log_group_name = var.log_group_name
  pattern        = "{ $.eventName = \"ConsoleLogin\" }"

  metric_transformation {
    name          = "ConsoleLoginCount"
    namespace     = "SiseonSecurity"
    value         = "1"
    default_value = "0"
  }
}

# CloudWatch Alarm - 삭제 작업
resource "aws_cloudwatch_metric_alarm" "delete_action" {
  alarm_name          = "${var.project_name}-alarm-delete-action"
  alarm_description   = "AWS 리소스 삭제/종료 작업 감지"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DeleteActionCount"
  namespace           = "SiseonSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
}

# CloudWatch Alarm - 콘솔 로그인
resource "aws_cloudwatch_metric_alarm" "console_login" {
  alarm_name          = "${var.project_name}-alarm-console-login"
  alarm_description   = "AWS 콘솔 로그인 감지"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleLoginCount"
  namespace           = "SiseonSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
}