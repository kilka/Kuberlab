# Flux GitOps Configuration using Azure Flux Extension
# This enables GitOps workflow without requiring kubeconfig during Terraform apply

# Install Flux extension on AKS cluster
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name              = "flux"
  cluster_id        = module.aks.cluster_id
  extension_type    = "microsoft.flux"
  release_namespace = "flux-system"
  
  depends_on = [module.aks]
}

# Generate SSH key for Flux to access private repo (only if private)
resource "tls_private_key" "flux" {
  count     = var.flux_repo_private ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store the private key in Key Vault (only if private)
resource "azurerm_key_vault_secret" "flux_ssh_key" {
  count        = var.flux_repo_private ? 1 : 0
  name         = "flux-ssh-private-key"
  value        = tls_private_key.flux[0].private_key_pem
  key_vault_id = module.keyvault.id
  
  depends_on = [module.keyvault]
}

# Configure Flux to sync from GitHub repository
resource "azurerm_kubernetes_flux_configuration" "main" {
  name       = "flux-system"
  cluster_id = module.aks.cluster_id
  namespace  = "flux-system"
  scope      = "cluster"
  
  git_repository {
    url                      = var.flux_repo_private ? "ssh://git@github.com/${var.github_username}/Kuberlab.git" : "https://github.com/${var.github_username}/Kuberlab"
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 300
    ssh_private_key_base64   = var.flux_repo_private ? base64encode(tls_private_key.flux[0].private_key_pem) : null
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
    sync_interval_in_seconds = 300
    retry_interval_in_seconds = 60
    timeout_in_seconds = 600
    garbage_collection_enabled = true
    recreating_enabled = false
  }
  
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux,
    module.aks
  ]
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

# Output SSH public key for GitHub deploy key (only if private repo)
output "flux_ssh_public_key" {
  value       = var.flux_repo_private ? tls_private_key.flux[0].public_key_openssh : "N/A - Using public repo"
  description = "Add this SSH public key as a deploy key to your GitHub repository with read access (only for private repos)"
  sensitive   = false
}