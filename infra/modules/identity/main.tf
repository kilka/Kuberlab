# API Managed Identity - minimal permissions for API service
resource "azurerm_user_assigned_identity" "api" {
  name                = "${var.identity_name}-api"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    component = "api"
  })
}

# Worker Managed Identity - permissions for processing jobs
resource "azurerm_user_assigned_identity" "worker" {
  name                = "${var.identity_name}-worker"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    component = "worker"
  })
}

# GitHub Actions Managed Identity - for CI/CD
resource "azurerm_user_assigned_identity" "github" {
  name                = "${var.identity_name}-github"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    component = "cicd"
  })
}

# Federated Identity Credential for GitHub OIDC
resource "azurerm_federated_identity_credential" "github" {
  name                = "github-oidc"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.github.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:ref:refs/heads/main"
}

# ===== API Identity Role Assignments =====
# API only needs to send messages to Service Bus
resource "azurerm_role_assignment" "api_service_bus_sender" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
}

# API needs to read uploaded images from blob storage
resource "azurerm_role_assignment" "api_storage_blob_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
}

# ===== Worker Identity Role Assignments =====
# Worker needs to receive messages from Service Bus
resource "azurerm_role_assignment" "worker_service_bus_receiver" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# Worker needs to read/write blob storage (read images, write results)
resource "azurerm_role_assignment" "worker_storage_blob_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# Worker needs to read/write table storage for job metadata
resource "azurerm_role_assignment" "worker_storage_table_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# ===== GitHub Identity Role Assignments =====
# GitHub Actions needs ACR push permissions (handled in ACR module to avoid circular dependency)

# Key Vault Secrets User role (handled in keyvault module)
# This avoids circular dependency issues