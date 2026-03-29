output "databricks_workspace_id"  { value = azurerm_databricks_workspace.main.id }
output "databricks_workspace_url" { value = azurerm_databricks_workspace.main.workspace_url }
output "databricks_principal_id"  { value = azurerm_databricks_workspace.main.storage_account_identity[0].principal_id }
