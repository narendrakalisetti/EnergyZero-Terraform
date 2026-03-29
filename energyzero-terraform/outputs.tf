/*
=============================================================================
Outputs – values exposed for downstream consumption / CI-CD
=============================================================================
*/

output "resource_group_name" {
  description = "Name of the main resource group."
  value       = azurerm_resource_group.main.name
}

output "adls_storage_account_name" {
  description = "ADLS Gen2 storage account name."
  value       = module.adls.storage_account_name
}

output "adls_dfs_endpoint" {
  description = "ADLS Gen2 DFS primary endpoint (abfss:// base)."
  value       = module.adls.dfs_primary_endpoint
}

output "adls_container_bronze" {
  description = "Bronze container name."
  value       = module.adls.container_bronze
}

output "adls_container_silver" {
  description = "Silver container name."
  value       = module.adls.container_silver
}

output "adls_container_gold" {
  description = "Gold container name."
  value       = module.adls.container_gold
}

output "key_vault_uri" {
  description = "Azure Key Vault URI for secret retrieval."
  value       = module.key_vault.key_vault_uri
}

output "key_vault_id" {
  description = "Azure Key Vault resource ID."
  value       = module.key_vault.key_vault_id
}

output "adf_name" {
  description = "Azure Data Factory instance name."
  value       = module.adf.adf_name
}

output "adf_id" {
  description = "Azure Data Factory resource ID."
  value       = module.adf.adf_id
}

output "adf_principal_id" {
  description = "ADF system-assigned managed identity principal ID (for RBAC)."
  value       = module.adf.adf_principal_id
}
