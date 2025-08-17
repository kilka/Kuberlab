output "account_id" {
  description = "Storage account ID"
  value       = azurerm_storage_account.main.id
}

output "account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.main.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "primary_access_key" {
  description = "Primary access key"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "secondary_access_key" {
  description = "Secondary access key"
  value       = azurerm_storage_account.main.secondary_access_key
  sensitive   = true
}

output "uploads_container_name" {
  description = "Uploads container name"
  value       = azurerm_storage_container.uploads.name
}

output "results_container_name" {
  description = "Results container name"
  value       = azurerm_storage_container.results.name
}

output "primary_table_endpoint" {
  description = "Primary table storage endpoint"
  value       = azurerm_storage_account.main.primary_table_endpoint
}