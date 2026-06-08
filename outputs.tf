output "cloudtrail_log_group" {
  value = module.cloudtrail.log_group_name
}

output "lambda_login_arn" {
  value = module.lambda.lambda_login_arn
}

output "lambda_delete_arn" {
  value = module.lambda.lambda_delete_arn
}

output "log_analytics_workspace_id" {
  value = module.azure_monitor.workspace_id
}

output "azure_monitor_workbook_id" {
  value = module.azure_monitor.workbook_id
}