# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = "${replace(var.name_prefix, "-", "")}acr${var.sequence}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false  # Use Azure AD authentication instead
  tags                = var.tags

  # Enable container image scanning for Premium SKU
  dynamic "retention_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      days    = 7
      enabled = true
    }
  }

  dynamic "trust_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      enabled = false
    }
  }

  # Quarantine policy for Premium SKU
  dynamic "quarantine_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      enabled = false
    }
  }
}