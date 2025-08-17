output "gateway_id" {
  description = "Application Gateway for Containers ID"
  value       = azurerm_application_load_balancer.main.id
}

output "gateway_name" {
  description = "Application Gateway for Containers name"
  value       = azurerm_application_load_balancer.main.name
}

output "frontend_id" {
  description = "Frontend configuration ID"
  value       = azurerm_application_load_balancer_frontend.main.id
}

output "association_id" {
  description = "Subnet association ID"
  value       = azurerm_application_load_balancer_subnet_association.main.id
}