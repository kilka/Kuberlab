output "id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}