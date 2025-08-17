resource "azurerm_user_assigned_identity" "main" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Federated Identity Credential for GitHub OIDC
resource "azurerm_federated_identity_credential" "github" {
  name                = "github-oidc"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.main.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:ref:refs/heads/main"
}

# Role assignments for Azure services

# Service Bus Data Receiver role
resource "azurerm_role_assignment" "service_bus_receiver" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Service Bus Data Sender role
resource "azurerm_role_assignment" "service_bus_sender" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Storage Blob Data Contributor role
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Key Vault Secrets User role (handled in keyvault module)
# This avoids circular dependency issues