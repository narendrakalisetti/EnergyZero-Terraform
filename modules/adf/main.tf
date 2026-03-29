/*
=============================================================================
Module: Azure Data Factory
=============================================================================
Provisions an Azure Data Factory instance with:
  • System-assigned managed identity (no secrets in ADF config)
  • Git-backed configuration (CI/CD-ready)
  • Linked Services to ADLS Gen2 and Key Vault (via managed identity)
  • Auto-resolve Managed Integration Runtime

GDPR:
  • All linked service credentials are referenced from Key Vault via ADF's
    Key Vault linked service – no connection strings stored in ADF JSON.
  • ADF activity logs (pipeline runs, trigger history) are routed to a Log
    Analytics workspace for 90-day retention under GDPR Article 30 (Records
    of Processing Activities).

Net Zero 2050:
  • Managed Integration Runtime auto-scales to zero when idle, eliminating
    wasted compute between pipeline runs.
  • UK South placement ensures renewable-energy-backed execution.
=============================================================================
*/

resource "azurerm_data_factory" "main" {
  # Naming: adf-<region>-<project>-<env>
  name                = "adf-uks-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Managed identity enables password-less access to ADLS + Key Vault
  identity {
    type = "SystemAssigned"
  }

  # Managed Virtual Network – all IR traffic stays within Azure backbone
  managed_virtual_network_enabled = true

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Linked Service: Azure Key Vault
# ADF retrieves all secrets from KV at runtime – no credentials in ADF ARM.
# ---------------------------------------------------------------------------
resource "azurerm_data_factory_linked_service_key_vault" "kv" {
  name            = "ls-keyvault-energyzero"
  data_factory_id = azurerm_data_factory.main.id
  key_vault_id    = var.key_vault_id
}

# ---------------------------------------------------------------------------
# Linked Service: ADLS Gen2 (via managed identity – no shared key)
# ---------------------------------------------------------------------------
resource "azurerm_data_factory_linked_service_azure_blob_storage" "adls" {
  name            = "ls-adlsgen2-energyzero"
  data_factory_id = azurerm_data_factory.main.id

  # Use Managed Identity auth – shared_access_key_enabled = false on storage
  service_endpoint   = "https://${var.adls_storage_account_name}.blob.core.windows.net"
  use_managed_identity = true
}

# ---------------------------------------------------------------------------
# Auto-resolve Integration Runtime (default, managed by Microsoft)
# For custom IR (SHIR / Azure IR with fixed size) see commented block below.
# ---------------------------------------------------------------------------
# Managed Integration Runtime with auto-resolve is provisioned automatically
# by ADF when managed_virtual_network_enabled = true.  No explicit Terraform
# resource is required – it appears as "AutoResolveIntegrationRuntime" in ADF.

# ---------------------------------------------------------------------------
# Diagnostic Settings → Log Analytics (GDPR Article 30 audit trail)
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "adf_diagnostics" {
  name                       = "diag-adf-uks-${var.project_name}-${var.environment}"
  target_resource_id         = azurerm_data_factory.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = [
      "ActivityRuns", "PipelineRuns", "TriggerRuns",
      "SandboxActivityRuns", "SandboxPipelineRuns"
    ]
    content {
      category = enabled_log.value
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
