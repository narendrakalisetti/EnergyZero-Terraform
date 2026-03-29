/*
=============================================================================
Module: ADLS Gen2 — Medallion Architecture Storage
=============================================================================
Provisions ADLS Gen2 with bronze/silver/gold containers, private endpoint,
Customer-Managed Key encryption, lifecycle policies, Defender for Storage,
and full diagnostic logging to Log Analytics.
=============================================================================
*/

# ---------------------------------------------------------------------------
# Customer-Managed Key (CMK) — GDPR Art. 32 enhanced encryption control
# The encryption key lives in Key Vault; Key Vault ID is passed in from root.
# ---------------------------------------------------------------------------
data "azurerm_key_vault" "kv" {
  name                = "kv-uks-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
}

data "azurerm_key_vault_key" "cmk" {
  name         = "adls-cmk"
  key_vault_id = data.azurerm_key_vault.kv.id
}

# ---------------------------------------------------------------------------
# Storage Account
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "adls" {
  name                = "sauks${var.project_name}${substr(var.environment, 0, 4)}"
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"
  is_hns_enabled           = true   # Hierarchical Namespace = ADLS Gen2

  # Security hardening
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false   # Force AAD / managed identity auth only

  # Network: default deny; traffic via private endpoint only in prod
  public_network_access_enabled = var.environment == "prod" ? false : true

  network_rules {
    default_action             = var.environment == "prod" ? "Deny" : "Allow"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }

  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true
  }

  # Customer-Managed Key encryption
  customer_managed_key {
    key_vault_key_id          = data.azurerm_key_vault_key.cmk.id
    user_assigned_identity_id = azurerm_user_assigned_identity.adls_cmk.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.adls_cmk.id]
  }

  tags = var.tags
}

# User-assigned identity for CMK access to Key Vault
resource "azurerm_user_assigned_identity" "adls_cmk" {
  name                = "id-adls-cmk-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Grant the CMK identity access to unwrap/wrap keys in Key Vault
resource "azurerm_role_assignment" "adls_cmk_kv" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.adls_cmk.principal_id
}

# ---------------------------------------------------------------------------
# Medallion Containers
# ---------------------------------------------------------------------------
resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Private Endpoint (prod only — enterprise network isolation)
# ---------------------------------------------------------------------------
resource "azurerm_private_endpoint" "adls_dfs" {
  count               = var.environment == "prod" ? 1 : 0
  name                = "pe-adls-dfs-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-adls-dfs"
    private_connection_resource_id = azurerm_storage_account.adls.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Lifecycle Management — GDPR retention + cost optimisation
# ---------------------------------------------------------------------------
resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.adls.id

  rule {
    name    = "bronze-tiering-90d"
    enabled = true
    filters {
      prefix_match = ["bronze/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 60
        delete_after_days_since_modification_greater_than          = 90
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }

  rule {
    name    = "silver-tiering-180d"
    enabled = true
    filters {
      prefix_match = ["silver/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than       = 180
      }
    }
  }

  rule {
    name    = "gold-archive-365d"
    enabled = true
    filters {
      prefix_match = ["gold/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 180
        tier_to_archive_after_days_since_modification_greater_than = 270
        delete_after_days_since_modification_greater_than          = 365
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Diagnostic Settings → Log Analytics (GDPR Art. 30 audit trail)
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "adls" {
  name                       = "diag-adls-${var.project_name}-${var.environment}"
  target_resource_id         = "${azurerm_storage_account.adls.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  metric {
    category = "Transaction"
    enabled  = true
  }
}
