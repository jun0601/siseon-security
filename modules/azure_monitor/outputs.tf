output "workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}

output "workbook_id" {
  value = azurerm_application_insights_workbook.security_audit.id
}