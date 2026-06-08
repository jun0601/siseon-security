# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.project_name}-security-logs"
  location            = var.resource_group_name
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    project     = var.project_name
    environment = "prod"
    purpose     = "cloudtrail-security-audit"
  }
}

# Azure Monitor Workbook (CloudTrail 보안 감사 대시보드)
resource "azurerm_application_insights_workbook" "security_audit" {
  name                = "${var.project_name}-cloudtrail-audit"
  resource_group_name = var.resource_group_name
  location            = var.resource_group_name
  display_name        = "🔐 StockOps CloudTrail 보안 감사 대시보드"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "## 🔐 StockOps CloudTrail 보안 감사 대시보드\n\nAWS CloudTrail 로그를 Azure Blob Storage에 백업하여 AWS 장애 시에도 보안 감사 로그를 조회할 수 있습니다."
        }
        name = "header"
      },
      {
        type = 9
        content = {
          version = "KqlParameterItem/1.0"
          parameters = [
            {
              name         = "TimeRange"
              type         = 4
              isRequired   = true
              value        = { durationMs = 86400000 }
              label        = "시간 범위"
            }
          ]
        }
        name = "parameters"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AzureActivity | where TimeGenerated {TimeRange} | summarize Count=count() by OperationName | order by Count desc | take 10"
          size         = 0
          title        = "📊 주요 작업 현황 (Top 10)"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "barchart"
        }
        name = "operations-chart"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AzureActivity | where TimeGenerated {TimeRange} | where ActivityStatusValue == 'Failure' | project TimeGenerated, OperationName, Caller, ResourceGroup | order by TimeGenerated desc"
          size         = 0
          title        = "🚨 실패한 작업 목록"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "table"
        }
        name = "failed-operations"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AzureActivity | where TimeGenerated {TimeRange} | summarize Count=count() by Caller | order by Count desc | take 10"
          size         = 0
          title        = "👤 사용자별 활동 현황"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "piechart"
        }
        name = "user-activity"
      }
    ]
    styleSettings = {}
    "$schema" = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
  })

  tags = {
    project     = var.project_name
    environment = "prod"
    purpose     = "cloudtrail-security-audit"
  }
}