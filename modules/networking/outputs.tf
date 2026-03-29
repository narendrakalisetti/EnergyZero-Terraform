output "vnet_id"                      { value = azurerm_virtual_network.main.id }
output "private_endpoint_subnet_id"   { value = azurerm_subnet.private_endpoints.id }
output "databricks_public_subnet_id"  { value = azurerm_subnet.databricks_public.id }
output "databricks_private_subnet_id" { value = azurerm_subnet.databricks_private.id }
