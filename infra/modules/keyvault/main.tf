data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id

  sku_name = "standard"

  # Security settings
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false

  # RBAC-based access control
  enable_rbac_authorization = true

  # Network access
  public_network_access_enabled = true
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  # Purge protection settings
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = 90

  tags = var.tags
}

# Store runtime configuration values as secrets
# These will be pulled by External Secrets Operator
resource "azurerm_key_vault_secret" "storage_account_name" {
  name         = "storage-account-name"
  value        = var.storage_account_name
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_admin]
}

resource "azurerm_key_vault_secret" "service_bus_namespace" {
  name         = "service-bus-namespace"
  value        = var.service_bus_namespace
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_admin]
}

resource "azurerm_key_vault_secret" "service_bus_queue" {
  name         = "service-bus-queue"
  value        = var.service_bus_queue
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_admin]
}

resource "azurerm_key_vault_secret" "key_vault_name" {
  name         = "key-vault-name"
  value        = azurerm_key_vault.main.name
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_admin]
}

# Role assignment for current user/service principal to manage Key Vault
resource "azurerm_role_assignment" "current_user_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignment for managed identity
resource "azurerm_role_assignment" "managed_identity_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.managed_identity_principal_id
}