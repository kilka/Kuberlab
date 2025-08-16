# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet-${var.sequence}"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# AKS Subnet
resource "azurerm_subnet" "aks" {
  name                 = "${var.name_prefix}-aks-subnet-${var.sequence}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# Application Gateway for Containers Subnet
resource "azurerm_subnet" "agc" {
  name                 = "${var.name_prefix}-agc-subnet-${var.sequence}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.agc_subnet_cidr]

  # Delegation required for Application Gateway for Containers
  delegation {
    name = "Microsoft.ServiceNetworking/trafficControllers"
    service_delegation {
      name    = "Microsoft.ServiceNetworking/trafficControllers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# PostgreSQL Subnet (delegated for database services)
resource "azurerm_subnet" "postgres" {
  name                 = "${var.name_prefix}-postgres-subnet-${var.sequence}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.postgres_subnet_cidr]

  delegation {
    name = "Microsoft.DBforPostgreSQL/flexibleServers"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Network Security Group for AKS subnet
resource "azurerm_network_security_group" "aks" {
  name                = "${var.name_prefix}-aks-nsg-${var.sequence}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow inbound from AGC subnet
  security_rule {
    name                       = "AllowAGCInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = var.agc_subnet_cidr
    destination_address_prefix = var.aks_subnet_cidr
  }

  # Allow outbound internet access for pulling images, etc.
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aks_subnet_cidr
    destination_address_prefix = "Internet"
  }
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Network Security Group for PostgreSQL subnet
resource "azurerm_network_security_group" "postgres" {
  name                = "${var.name_prefix}-postgres-nsg-${var.sequence}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow inbound from AKS subnet only
  security_rule {
    name                       = "AllowAKSPostgres"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.aks_subnet_cidr
    destination_address_prefix = var.postgres_subnet_cidr
  }
}

# Associate NSG with PostgreSQL subnet
resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.postgres.id
}