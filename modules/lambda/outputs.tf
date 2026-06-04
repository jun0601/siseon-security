output "lambda_login_arn" {
  value = aws_lambda_function.login_alert.arn
}

output "lambda_delete_arn" {
  value = aws_lambda_function.delete_alert.arn
}