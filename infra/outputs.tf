output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "aks_kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = module.aks.kube_config_raw
  sensitive   = true
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = module.acr.login_server
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = module.acr.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = module.storage.account_name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = module.storage.primary_blob_endpoint
}

output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = module.postgresql.fqdn
}

output "postgresql_database_name" {
  description = "Name of the PostgreSQL database"
  value       = module.postgresql.database_name
}

output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = module.servicebus.namespace_name
}

output "service_bus_queue_name" {
  description = "Name of the Service Bus queue"
  value       = module.servicebus.queue_name
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.keyvault.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.keyvault.vault_uri
}

output "workload_identity_client_id" {
  description = "Client ID of the workload identity"
  value       = module.identity.client_id
}

output "workload_identity_principal_id" {
  description = "Principal ID of the workload identity"
  value       = module.identity.principal_id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = module.monitoring.workspace_id
}