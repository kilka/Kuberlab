data "azurerm_client_config" "current" {}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version

  # Entra ID (AAD) RBAC Integration
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
    tenant_id          = var.tenant_id != null ? var.tenant_id : data.azurerm_client_config.current.tenant_id
  }

  # OIDC Issuer for Workload Identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Network Configuration - Azure CNI
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    dns_service_ip    = var.dns_service_ip
    service_cidr      = var.service_cidr
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  # System Node Pool
  default_node_pool {
    name                 = "system"
    node_count           = var.system_node_count
    min_count            = var.system_node_min_count
    max_count            = var.system_node_max_count
    enable_auto_scaling  = true
    vm_size              = var.system_node_vm_size
    vnet_subnet_id       = var.subnet_id
    orchestrator_version = var.kubernetes_version

    # Security and performance
    only_critical_addons_enabled = true
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 30

    upgrade_settings {
      max_surge = "33%"
    }

    node_labels = {
      "node-type" = "system"
    }

    # Note: node_taints removed - not supported on default pool
    # Using only_critical_addons_enabled=true for system pool isolation
  }

  # Identity
  identity {
    type = "SystemAssigned"
  }

  # Security and compliance
  private_cluster_enabled           = false
  role_based_access_control_enabled = true

  # Monitoring
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # Additional security features
  local_account_disabled = false # Enabled for demo automation - would disable in production

  # Cost optimization
  automatic_channel_upgrade = "patch"
  node_os_channel_upgrade   = "NodeImage"

  # Maintenance window
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  tags = var.tags
}

# User Node Pool for application workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count
  min_count             = var.user_node_min_count
  max_count             = var.user_node_max_count
  enable_auto_scaling   = true
  vnet_subnet_id        = var.subnet_id
  orchestrator_version  = var.kubernetes_version

  # Performance and cost optimization
  os_disk_type    = "Ephemeral"
  os_disk_size_gb = 30

  # Regular instances for reliability (spot instances were causing provisioning issues)
  priority        = "Regular"
  
  node_labels = {
    "node-type" = "user"
  }
  
  # No taints - allow all workloads to schedule

  tags = var.tags
}

# Role assignment for AKS to pull from ACR will be handled in main.tf
# This is because it requires both AKS and ACR resource IDs