output "storage_account_name"  { value = azurerm_storage_account.adls.name }
output "storage_account_id"    { value = azurerm_storage_account.adls.id }
output "dfs_primary_endpoint"  { value = azurerm_storage_account.adls.primary_dfs_endpoint }
output "container_bronze"      { value = azurerm_storage_container.bronze.name }
output "container_silver"      { value = azurerm_storage_container.silver.name }
output "container_gold"        { value = azurerm_storage_container.gold.name }
