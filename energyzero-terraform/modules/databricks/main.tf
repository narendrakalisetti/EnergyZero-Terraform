/*
=============================================================================
Module: Azure Databricks Workspace
=============================================================================
Provisions a VNet-injected Databricks workspace with cluster policies
enforcing auto-termination (Net Zero 2050 cost/carbon efficiency).
=============================================================================
*/

resource "azurerm_databricks_workspace" "main" {
  name                = "dbw-uks-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "premium"   # Premium required for VNet injection + Unity Catalog

  # VNet injection — all cluster traffic stays within the private network
  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = var.vnet_id
    public_subnet_name                                   = "snet-databricks-public"
    private_subnet_name                                  = "snet-databricks-private"
    public_subnet_network_security_group_association_id  = var.nsg_association_id
    private_subnet_network_security_group_association_id = var.nsg_association_id
  }

  managed_resource_group_name = "rg-uks-${var.project_name}-${var.environment}-databricks-managed"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Cluster Policy — enforce auto-termination after 20 min idle
# Prevents runaway compute costs and reduces carbon footprint (Net Zero 2050)
# ---------------------------------------------------------------------------
resource "azurerm_databricks_cluster_policy" "auto_terminate" {
  workspace_id = azurerm_databricks_workspace.main.id
  name         = "EnergyZero-AutoTerminate-Policy"

  definition = jsonencode({
    "autotermination_minutes" = {
      "type"  = "fixed"
      "value" = 20
      "hidden" = false
    }
    "spark_version" = {
      "type"         = "allowlist"
      "values"       = ["13.3.x-scala2.12", "14.3.x-scala2.12"]
      "defaultValue" = "14.3.x-scala2.12"
    }
    "node_type_id" = {
      "type"         = "allowlist"
      "values"       = ["Standard_DS3_v2", "Standard_DS4_v2"]
      "defaultValue" = "Standard_DS3_v2"
    }
    "data_security_mode" = {
      "type"  = "fixed"
      "value" = "SINGLE_USER"
    }
  })
}

# Diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "databricks" {
  name                       = "diag-dbw-${var.project_name}-${var.environment}"
  target_resource_id         = azurerm_databricks_workspace.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "dbfs" }
  enabled_log { category = "clusters" }
  enabled_log { category = "jobs" }
  enabled_log { category = "notebook" }
}
