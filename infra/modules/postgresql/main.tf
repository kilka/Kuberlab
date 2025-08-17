resource "random_password" "admin" {
  length  = 16
  special = true
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                = var.server_name
  resource_group_name = var.resource_group_name
  location            = var.location

  administrator_login    = var.admin_username
  administrator_password = random_password.admin.result

  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  version    = var.postgresql_version

  # Network configuration
  delegated_subnet_id = var.subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.main.id
  
  # Required when using VNet integration
  public_network_access_enabled = false

  # Security settings
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # High availability settings disabled for cost optimization

  # Maintenance window
  maintenance_window {
    day_of_week  = 0 # Sunday
    start_hour   = 2
    start_minute = 0
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.main]

  tags = var.tags
}

# Private DNS zone for PostgreSQL
resource "azurerm_private_dns_zone" "main" {
  name                = "${var.server_name}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Link private DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "${var.server_name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = var.virtual_network_id

  tags = var.tags
}

# Database for OCR application
resource "azurerm_postgresql_flexible_server_database" "ocr" {
  name      = "ocr"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Note: Store password in Key Vault manually or via separate step
# to avoid circular dependencies during initial deployment