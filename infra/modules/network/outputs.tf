output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "aks_subnet_name" {
  description = "Name of the AKS subnet"
  value       = azurerm_subnet.aks.name
}

output "agc_subnet_id" {
  description = "ID of the Application Gateway for Containers subnet"
  value       = azurerm_subnet.agc.id
}

output "agc_subnet_name" {
  description = "Name of the Application Gateway for Containers subnet"
  value       = azurerm_subnet.agc.name
}

