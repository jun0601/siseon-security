# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.project_name}-security-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    project     = var.project_name
    environment = "prod"
    purpose     = "cloudtrail-security-audit"
  }
}

# Azure Function을 위한 Storage Account
resource "azurerm_storage_account" "function" {
  name                     = "${var.project_name}funcstore"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    project = var.project_name
  }
}

# App Service Plan (Consumption - 무료 티어)
resource "azurerm_service_plan" "function" {
  name                = "${var.project_name}-func-plan"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = {
    project = var.project_name
  }
}

# Azure Function App
resource "azurerm_linux_function_app" "blob_to_laws" {
  name                       = "${var.project_name}-blob-to-laws"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key

  app_settings = {
    LOG_ANALYTICS_WORKSPACE_ID  = azurerm_log_analytics_workspace.this.workspace_id
    LOG_ANALYTICS_WORKSPACE_KEY = azurerm_log_analytics_workspace.this.primary_shared_key
    AZURE_BLOB_CONNECTION_STRING = var.azure_connection_string
    FUNCTIONS_WORKER_RUNTIME    = "python"
    AzureWebJobsFeatureFlags    = "EnableWorkerIndexing"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  tags = {
    project     = var.project_name
    environment = "prod"
    purpose     = "blob-to-log-analytics"
  }
}

# Workbook
resource "azurerm_application_insights_workbook" "security_audit" {
  name                = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "StockOps CloudTrail 보안 감사 대시보드"

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
              name       = "TimeRange"
              type       = 4
              isRequired = true
              value      = { durationMs = 86400000 }
              label      = "시간 범위"
            }
          ]
        }
        name = "parameters"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "CloudTrailLogs_CL | where TimeGenerated {TimeRange} | summarize Count=count() by EventName_s | order by Count desc | take 10"
          size         = 0
          title        = "📊 CloudTrail 이벤트 현황 (Top 10)"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "barchart"
          crossComponentResources = [
            "/subscriptions/41ba8281-70ed-41df-979f-13eef4480f49/resourceGroups/siseon-rg/providers/Microsoft.OperationalInsights/workspaces/siseon-security-logs"
          ]
        }
        name = "events-chart"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "CloudTrailLogs_CL | where TimeGenerated {TimeRange} | where isnotempty(ErrorCode_s) | project TimeGenerated, EventName_s, ErrorCode_s, ErrorMessage_s, SourceIPAddress_s | order by TimeGenerated desc"
          size         = 0
          title        = "🚨 오류 발생 이벤트"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "table"
          crossComponentResources = [
            "/subscriptions/41ba8281-70ed-41df-979f-13eef4480f49/resourceGroups/siseon-rg/providers/Microsoft.OperationalInsights/workspaces/siseon-security-logs"
          ]
        }
        name = "error-events"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "CloudTrailLogs_CL | where TimeGenerated {TimeRange} | summarize Count=count() by SourceIPAddress_s | order by Count desc | take 10"
          size         = 0
          title        = "🌐 소스 IP별 접근 현황"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "piechart"
          crossComponentResources = [
            "/subscriptions/41ba8281-70ed-41df-979f-13eef4480f49/resourceGroups/siseon-rg/providers/Microsoft.OperationalInsights/workspaces/siseon-security-logs"
          ]
        }
        name = "ip-activity"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "CloudTrailLogs_CL | where TimeGenerated {TimeRange} | summarize Count=count() by bin(TimeGenerated, 1h) | order by TimeGenerated asc"
          size         = 0
          title        = "📈 시간대별 이벤트 추이"
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "timechart"
          crossComponentResources = [
            "/subscriptions/41ba8281-70ed-41df-979f-13eef4480f49/resourceGroups/siseon-rg/providers/Microsoft.OperationalInsights/workspaces/siseon-security-logs"
          ]
        }
        name = "time-series"
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