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
  location            = azurerm_resource_group.main.location
  name_prefix         = local.name_prefix
  sequence            = var.sequence
  tags                = local.common_tags
}

# Azure Container Registry
module "acr" {
  source = "./modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = local.name_prefix
  sequence            = var.sequence
  tags                = local.common_tags
}

# Monitoring (Log Analytics)
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = local.name_prefix
  sequence            = var.sequence
  tags                = local.common_tags
}

# AKS Cluster
module "aks" {
  source = "./modules/aks"

  cluster_name               = "${local.name_prefix}-aks-${var.sequence}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  dns_prefix                 = "${local.name_prefix}-aks-${var.sequence}"
  subnet_id                  = module.network.aks_subnet_id
  log_analytics_workspace_id = module.monitoring.workspace_id
  tenant_id                  = local.tenant_id
  
  # Node configuration - Updated VM sizes due to capacity issues
  system_node_vm_size   = "Standard_B2ms"  # Changed from default B2s
  user_node_vm_size     = "Standard_B2ms"  # Changed from default B2s
  user_node_min_count   = 1                # Changed from 0 to ensure KEDA/workloads can run
  
  tags = local.common_tags
  
  depends_on = [
    module.network,
    module.monitoring
  ]
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = module.aks.kubelet_identity.object_id
  role_definition_name             = "AcrPull"
  scope                            = module.acr.registry_id
  skip_service_principal_aad_check = true
}

# Role assignment for GitHub identity to push to ACR
resource "azurerm_role_assignment" "github_acr_push" {
  principal_id                     = module.identity.github_principal_id
  role_definition_name             = "AcrPush"
  scope                            = module.acr.registry_id
  skip_service_principal_aad_check = true
}

# Role assignment for ALB Controller - AppGw for Containers Configuration Manager on RG
resource "azurerm_role_assignment" "alb_agc_manager" {
  principal_id                     = module.aks.kubelet_identity.object_id
  role_definition_id               = "/providers/Microsoft.Authorization/roleDefinitions/fbc52c3f-28ad-4303-a892-8a056630b8f1"
  scope                            = azurerm_resource_group.main.id
  skip_service_principal_aad_check = true
}

# Role assignment for ALB Controller - Network Contributor on AGC subnet
resource "azurerm_role_assignment" "alb_network_contributor" {
  principal_id                     = module.aks.kubelet_identity.object_id
  role_definition_name             = "Network Contributor"
  scope                            = module.network.agc_subnet_id
  skip_service_principal_aad_check = true
}

# Application Gateway for Containers
module "agc" {
  source = "./modules/agc"

  gateway_name        = "${local.name_prefix}-agc-${var.sequence}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = local.name_prefix
  subnet_id           = module.network.agc_subnet_id
  tags                = local.common_tags
  
  depends_on = [
    module.network
  ]
}

# Service Bus
module "servicebus" {
  source = "./modules/servicebus"

  namespace_name      = "${local.name_prefix}-sb-${var.sequence}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  tags                = local.common_tags
}

# Storage Account
module "storage" {
  source = "./modules/storage"

  resource_group_name  = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
  storage_account_name = local.storage_account_name
  tags                 = local.common_tags
}

# Database: Using Azure Table Storage (part of Storage Account)
# No separate database module needed - job metadata stored in Table Storage

# Managed Identity for Workload Identity
module "identity" {
  source = "./modules/identity"

  identity_name            = "${local.name_prefix}-id-${var.sequence}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  github_repository        = var.github_repository
  service_bus_namespace_id = module.servicebus.namespace_id
  storage_account_id       = module.storage.account_id
  aks_oidc_issuer_url      = module.aks.oidc_issuer_url
  tags                     = local.common_tags
  
  depends_on = [
    module.aks
  ]
}

# Key Vault
module "keyvault" {
  source = "./modules/keyvault"

  key_vault_name                = "${local.name_prefix}-kv-${var.sequence}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tenant_id                     = local.tenant_id
  api_identity_principal_id    = module.identity.api_principal_id
  worker_identity_principal_id = module.identity.worker_principal_id
  github_identity_principal_id = module.identity.github_principal_id
  
  # Configuration values to store as secrets for ESO
  storage_account_name     = module.storage.account_name
  service_bus_namespace    = module.servicebus.namespace_name
  service_bus_queue        = module.servicebus.queue_name
  service_bus_poison_queue = module.servicebus.poison_queue_name
  
  # Connection strings for the applications
  service_bus_connection_string = module.servicebus.namespace_primary_connection_string
  storage_connection_string     = "DefaultEndpointsProtocol=https;AccountName=${module.storage.account_name};AccountKey=${module.storage.primary_access_key};EndpointSuffix=core.windows.net"
  
  tags = local.common_tags
}

# Kubernetes and Helm providers are configured in providers.tf