output "alarm_delete_arn" {
  value = aws_cloudwatch_metric_alarm.delete_action.arn
}

output "alarm_login_arn" {
  value = aws_cloudwatch_metric_alarm.console_login.arn
}