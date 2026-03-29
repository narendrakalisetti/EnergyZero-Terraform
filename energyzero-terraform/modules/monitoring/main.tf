/*
=============================================================================
Module: Monitoring — Log Analytics, Alerts, Dashboards
=============================================================================
Centralised observability for all EnergyZero platform components.
GDPR Art. 30: pipeline run logs retained 90 days for records of processing.
=============================================================================
*/

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-uks-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 90   # GDPR Art. 30 — records of processing activities

  tags = var.tags
}

# Alert: ADF pipeline failure
resource "azurerm_monitor_action_group" "data_team" {
  name                = "ag-data-team-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "DataTeam"

  email_receiver {
    name                    = "DataEngineeringTeam"
    email_address           = "data-platform-team@energyzero.co.uk"
    use_common_alert_schema = true
  }

  tags = var.tags
}

# Alert: ADF pipeline failed runs > 0 in last 5 minutes
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "adf_pipeline_failures" {
  name                = "alert-adf-pipeline-failures-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1

  criteria {
    query = <<-QUERY
      AzureDiagnostics
      | where ResourceType == "FACTORIES/PIPELINERUNS"
      | where status_s == "Failed"
      | summarize FailedRuns = count() by bin(TimeGenerated, 5m)
      | where FailedRuns > 0
    QUERY
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.data_team.id]
  }

  tags = var.tags
}

# Alert: ADLS unauthorised access attempts
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "adls_auth_failures" {
  name                = "alert-adls-auth-failures-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1

  criteria {
    query = <<-QUERY
      StorageBlobLogs
      | where StatusCode == 403
      | summarize UnauthorisedAttempts = count() by bin(TimeGenerated, 5m), CallerIpAddress
      | where UnauthorisedAttempts > 5
    QUERY
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.data_team.id]
  }

  tags = var.tags
}
