# Flux GitOps Configuration using Azure Flux Extension
# This enables GitOps workflow without requiring kubeconfig during Terraform apply

# Install Flux extension on AKS cluster
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name              = "flux"
  cluster_id        = module.aks.cluster_id
  extension_type    = "microsoft.flux"
  release_namespace = "flux-system"
  
  depends_on = [module.aks]
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "10m"
  }
}

# Configure Flux to sync from public GitHub repository
# No authentication needed since the repo is public
resource "azurerm_kubernetes_flux_configuration" "main" {
  name       = "flux-system"
  cluster_id = module.aks.cluster_id
  namespace  = "flux-system"
  scope      = "cluster"
  
  git_repository {
    url                      = "https://github.com/kilka/Kuberlab"  # Public repo - anyone can deploy
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 300
    # No authentication needed for public repo
  }
  
  kustomizations {
    name = "infrastructure"
    path = "./clusters/demo/infrastructure"
    
    # Ensure infrastructure components are deployed first
    sync_interval_in_seconds = 300
    retry_interval_in_seconds = 60
    timeout_in_seconds = 600
    garbage_collection_enabled = true
    recreating_enabled = false
  }
  
  kustomizations {
    name = "controllers"
    path = "./clusters/demo/controllers"
    
    # Controllers depend on infrastructure
    depends_on = ["infrastructure"]
    sync_interval_in_seconds = 300
    retry_interval_in_seconds = 60
    timeout_in_seconds = 600
    garbage_collection_enabled = true
    recreating_enabled = false
  }
  
  kustomizations {
    name = "apps"
    path = "./clusters/demo/apps"
    
    # Applications depend on controllers
    depends_on = ["controllers"]
    
    # Variable substitution from the handoff Secret
    post_build {
      substitute_from {
        kind = "Secret"
        name = "cluster-config"
        optional = false
      }
    }
    
    sync_interval_in_seconds = 300
    retry_interval_in_seconds = 60
    timeout_in_seconds = 600
    garbage_collection_enabled = true
    recreating_enabled = false
  }
  
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux,
    module.aks,
    null_resource.build_docker_images  # Ensure images are ready before Flux deploys apps
  ]
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "1m"  # Short timeout - we remove from state anyway
  }
}

# Output Flux status
output "flux_status" {
  value = {
    extension_id = azurerm_kubernetes_cluster_extension.flux.id
    config_id    = azurerm_kubernetes_flux_configuration.main.id
    repository   = azurerm_kubernetes_flux_configuration.main.git_repository[0].url
  }
  description = "Flux GitOps configuration status"
}

