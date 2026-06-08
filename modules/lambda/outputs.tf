output "lambda_login_arn" {
  value = aws_lambda_function.login_alert.arn
}

output "lambda_delete_arn" {
  value = aws_lambda_function.delete_alert.arn
}

output "lambda_billing_arn" {
  value = aws_lambda_function.billing_alert.arn
}

output "lambda_s3_to_azure_arn" {
  value = aws_lambda_function.s3_to_azure.arn
}