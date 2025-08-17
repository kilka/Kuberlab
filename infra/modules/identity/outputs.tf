# API Identity Outputs
output "api_identity_id" {
  description = "API managed identity ID"
  value       = azurerm_user_assigned_identity.api.id
}

output "api_principal_id" {
  description = "API managed identity principal ID"
  value       = azurerm_user_assigned_identity.api.principal_id
}

output "api_client_id" {
  description = "API managed identity client ID"
  value       = azurerm_user_assigned_identity.api.client_id
}

output "api_identity_name" {
  description = "API managed identity name"
  value       = azurerm_user_assigned_identity.api.name
}

# Worker Identity Outputs
output "worker_identity_id" {
  description = "Worker managed identity ID"
  value       = azurerm_user_assigned_identity.worker.id
}

output "worker_principal_id" {
  description = "Worker managed identity principal ID"
  value       = azurerm_user_assigned_identity.worker.principal_id
}

output "worker_client_id" {
  description = "Worker managed identity client ID"
  value       = azurerm_user_assigned_identity.worker.client_id
}

output "worker_identity_name" {
  description = "Worker managed identity name"
  value       = azurerm_user_assigned_identity.worker.name
}

# GitHub Identity Outputs
output "github_identity_id" {
  description = "GitHub managed identity ID"
  value       = azurerm_user_assigned_identity.github.id
}

output "github_principal_id" {
  description = "GitHub managed identity principal ID"
  value       = azurerm_user_assigned_identity.github.principal_id
}

output "github_client_id" {
  description = "GitHub managed identity client ID"
  value       = azurerm_user_assigned_identity.github.client_id
}

output "github_identity_name" {
  description = "GitHub managed identity name"
  value       = azurerm_user_assigned_identity.github.name
}

# Legacy outputs for backward compatibility (pointing to GitHub identity for CI/CD)
output "id" {
  description = "User-assigned managed identity ID (GitHub identity for backward compatibility)"
  value       = azurerm_user_assigned_identity.github.id
}

output "principal_id" {
  description = "Principal ID of the managed identity (GitHub identity for backward compatibility)"
  value       = azurerm_user_assigned_identity.github.principal_id
}

output "client_id" {
  description = "Client ID of the managed identity (GitHub identity for backward compatibility)"
  value       = azurerm_user_assigned_identity.github.client_id
}

output "name" {
  description = "Name of the managed identity (GitHub identity for backward compatibility)"
  value       = azurerm_user_assigned_identity.github.name
}