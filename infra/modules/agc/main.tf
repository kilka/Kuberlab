# Application Gateway for Containers (AGC)
# This is the new Azure Application Load Balancer resource for container workloads

resource "azurerm_application_load_balancer" "main" {
  name                = var.gateway_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Frontend configuration for AGC
resource "azurerm_application_load_balancer_frontend" "main" {
  name                         = "${var.name_prefix}-frontend"
  application_load_balancer_id = azurerm_application_load_balancer.main.id

  tags = var.tags
}

# Associate AGC with subnet
resource "azurerm_application_load_balancer_subnet_association" "main" {
  name                         = "${var.name_prefix}-association"
  application_load_balancer_id = azurerm_application_load_balancer.main.id
  subnet_id                    = var.subnet_id

  tags = var.tags
}

# Role assignments for ALB Controller to manage AGC resources
resource "azurerm_role_assignment" "alb_agc_contributor" {
  scope                = azurerm_application_load_balancer.main.id
  role_definition_name = "Contributor"
  principal_id         = var.alb_identity_principal_id
}

resource "azurerm_role_assignment" "alb_subnet_reader" {
  scope                = var.subnet_id
  role_definition_name = "Reader"
  principal_id         = var.alb_identity_principal_id
}