# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg-${var.sequence}"
  location = var.location
  tags     = local.common_tags
}

# Network Module
module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  tags               = local.common_tags
}

# Azure Container Registry
module "acr" {
  source = "./modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  tags               = local.common_tags
}

# Monitoring (Log Analytics)
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  tags               = local.common_tags
}

# AKS Cluster
module "aks" {
  source = "./modules/aks"

  resource_group_name           = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  name_prefix                  = local.name_prefix
  sequence                     = var.sequence
  subnet_id                    = module.network.aks_subnet_id
  log_analytics_workspace_id   = module.monitoring.workspace_id
  admin_group_object_id        = var.admin_group_object_id
  tags                         = local.common_tags
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = module.aks.kubelet_identity_object_id
  role_definition_name             = "AcrPull"
  scope                           = module.acr.id
  skip_service_principal_aad_check = true
}

# Application Gateway for Containers
module "agc" {
  source = "./modules/agc"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  subnet_id          = module.network.agc_subnet_id
  tags               = local.common_tags
}

# Service Bus
module "servicebus" {
  source = "./modules/servicebus"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  tags               = local.common_tags
}

# Storage Account
module "storage" {
  source = "./modules/storage"

  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  storage_account_name     = local.storage_account_name
  tags                     = local.common_tags
}

# PostgreSQL Database
module "postgresql" {
  source = "./modules/postgresql"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  subnet_id          = module.network.postgres_subnet_id
  tags               = local.common_tags
}

# Key Vault
module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  name_prefix        = local.name_prefix
  sequence           = var.sequence
  tenant_id          = local.tenant_id
  tags               = local.common_tags
}

# Managed Identity for Workload Identity
module "identity" {
  source = "./modules/identity"

  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  name_prefix             = local.name_prefix
  sequence                = var.sequence
  tenant_id               = local.tenant_id
  github_repository       = var.github_repository
  service_bus_namespace_id = module.servicebus.namespace_id
  storage_account_id      = module.storage.account_id
  key_vault_id           = module.keyvault.id
  tags                   = local.common_tags
}

# Kubernetes and Helm providers configuration
provider "kubernetes" {
  host                   = module.aks.kube_config.0.host
  client_certificate     = base64decode(module.aks.kube_config.0.client_certificate)
  client_key            = base64decode(module.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.kube_config.0.host
    client_certificate     = base64decode(module.aks.kube_config.0.client_certificate)
    client_key            = base64decode(module.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config.0.cluster_ca_certificate)
  }
}