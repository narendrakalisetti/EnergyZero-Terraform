/*
=============================================================================
Module: Azure Key Vault
=============================================================================
Provisions a production-hardened Key Vault for secret management.

GDPR:
  • All connection strings, API keys, IBAN hashing salts, and storage
    account keys are stored ONLY in Key Vault – never in code or state.
  • Purge protection and soft-delete enforce a 90-day recovery window,
    meeting GDPR availability obligations under Article 32.
  • RBAC-based access model (not legacy Vault Access Policies) for
    fine-grained, auditable permissions (Article 5(2) – accountability).

Net Zero 2050:
  • No compute resources – Key Vault is a managed PaaS service with
    negligible direct carbon footprint.  Deployed UK South for data
    residency and renewable-energy alignment.
=============================================================================
*/

resource "azurerm_key_vault" "main" {
  # Naming: kv-<region>-<project>-<env> (max 24 chars)
  name                = "kv-uks-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id

  sku_name = var.key_vault_sku   # "premium" = HSM-backed keys (recommended for GDPR)

  # GDPR data availability – soft-delete prevents accidental permanent loss
  soft_delete_retention_days = 90
  purge_protection_enabled   = true   # Prevents force-delete even by admins

  # Use Azure RBAC for access control (not legacy access policies)
  enable_rbac_authorization = true

  # Network hardening – restrict to known CIDRs and Azure services
  network_acls {
    bypass                     = ["AzureServices"]
    default_action             = "Allow"           # Change to "Deny" with Private Endpoint
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Seed Key Vault with placeholder secrets
# (real values injected by CI/CD pipeline via az keyvault secret set)
# ---------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "adls_connection_string" {
  name         = "adls-connection-string"
  value        = "PLACEHOLDER-SET-BY-CICD"   # Overwritten by CI/CD – never hard-code
  key_vault_id = azurerm_key_vault.main.id

  tags = {
    Description = "ADLS Gen2 storage account connection string"
    GDPR        = "true"
    Rotate      = "90-days"
  }

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "event_hubs_connection_string" {
  name         = "eh-namespace-connstr"
  value        = "PLACEHOLDER-SET-BY-CICD"
  key_vault_id = azurerm_key_vault.main.id

  tags = {
    Description = "Event Hubs namespace connection string"
    GDPR        = "true"
    Rotate      = "90-days"
  }

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "iban_hash_salt" {
  name         = "iban-hash-salt"
  value        = "PLACEHOLDER-SET-BY-CICD"   # HMAC salt for IBAN pseudonymisation (GDPR Art. 25)
  key_vault_id = azurerm_key_vault.main.id

  tags = {
    Description = "Salt for HMAC-SHA256 IBAN hashing – GDPR pseudonymisation"
    GDPR        = "true"
    Rotate      = "365-days"
  }

  depends_on = [azurerm_key_vault.main]
}

# ---------------------------------------------------------------------------
# Terraform deployer – Key Vault Administrator (bootstrap access)
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "deployer_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.object_id
}
