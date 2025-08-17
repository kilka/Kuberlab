# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = "${replace(var.name_prefix, "-", "")}acr${var.sequence}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false # Use Azure AD authentication instead
  tags                = var.tags

  # Note: retention_policy and trust_policy are only available for Premium SKU
  # These would need to be configured separately if using Premium

}