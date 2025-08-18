# Handoff configuration from Terraform to Flux
# This creates a minimal Secret with non-sensitive configuration values
# that Flux will use for variable substitution via postBuild.substituteFrom

# Namespace for Flux (should already exist, but ensure it's there)
resource "kubernetes_namespace" "flux_system" {
  metadata {
    name = "flux-system"
  }
  
  depends_on = [module.aks]
}

# Namespace for OCR application (if not already created by Flux)
resource "kubernetes_namespace" "ocr" {
  metadata {
    name = "ocr"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "workload-identity"                  = "enabled"
    }
  }
  
  depends_on = [module.aks]
}

# The handoff Secret with computed Azure resource names
# These are non-sensitive configuration values that Flux needs
# Must be in flux-system namespace for Flux Kustomizations to access it
resource "kubernetes_secret" "cluster_config" {
  metadata {
    name      = "cluster-config"
    namespace = kubernetes_namespace.flux_system.metadata[0].name
  }
  
  data = {
    # Azure resource names for Flux substitution
    KEY_VAULT_NAME                = module.keyvault.vault_name
    STORAGE_ACCOUNT_NAME          = module.storage.account_name
    SERVICE_BUS_NAMESPACE         = module.servicebus.namespace_name
    SERVICE_BUS_QUEUE             = module.servicebus.queue_name
    SERVICE_BUS_POISON_QUEUE      = module.servicebus.poison_queue_name
    API_IDENTITY_CLIENT_ID        = module.identity.api_client_id
    WORKER_IDENTITY_CLIENT_ID     = module.identity.worker_client_id
    GITHUB_IDENTITY_CLIENT_ID     = module.identity.github_client_id
    TENANT_ID                     = local.tenant_id
    KUBELET_IDENTITY_CLIENT_ID    = module.aks.kubelet_identity.client_id
    ACR_NAME                      = module.acr.name
    AZURE_SUBSCRIPTION_ID         = data.azurerm_client_config.current.subscription_id
    RESOURCE_GROUP                = azurerm_resource_group.main.name
    AGC_NAME                      = module.agc.gateway_name
    AGC_FRONTEND_NAME             = "dev-ocr-frontend"
    ALB_IDENTITY_CLIENT_ID        = module.identity.alb_client_id
    # Legacy for backward compatibility
    WORKLOAD_IDENTITY_CLIENT_ID   = module.identity.github_client_id
  }
  
  type = "Opaque"
  
  depends_on = [
    module.aks,
    module.keyvault,
    module.storage,
    module.servicebus,
    module.identity
  ]
}

# Also create the secret in ocr namespace for ESO SecretStore
# Azure Flux doesn't support postBuild substitution, so ESO needs direct access
resource "kubernetes_secret" "cluster_config_ocr" {
  metadata {
    name      = "cluster-config"
    namespace = kubernetes_namespace.ocr.metadata[0].name
  }
  
  data = {
    # Azure resource names for ESO SecretStore
    KEY_VAULT_NAME                = module.keyvault.vault_name
    STORAGE_ACCOUNT_NAME          = module.storage.account_name
    SERVICE_BUS_NAMESPACE         = module.servicebus.namespace_name
    SERVICE_BUS_QUEUE             = module.servicebus.queue_name
    SERVICE_BUS_POISON_QUEUE      = module.servicebus.poison_queue_name
    API_IDENTITY_CLIENT_ID        = module.identity.api_client_id
    WORKER_IDENTITY_CLIENT_ID     = module.identity.worker_client_id
    GITHUB_IDENTITY_CLIENT_ID     = module.identity.github_client_id
    TENANT_ID                     = local.tenant_id
    KUBELET_IDENTITY_CLIENT_ID    = module.aks.kubelet_identity.client_id
    ACR_NAME                      = module.acr.name
    AZURE_SUBSCRIPTION_ID         = data.azurerm_client_config.current.subscription_id
    RESOURCE_GROUP                = azurerm_resource_group.main.name
    AGC_NAME                      = module.agc.gateway_name
    AGC_FRONTEND_NAME             = "dev-ocr-frontend"
    ALB_IDENTITY_CLIENT_ID        = module.identity.alb_client_id
    # Legacy for backward compatibility
    WORKLOAD_IDENTITY_CLIENT_ID   = module.identity.github_client_id
  }
  
  type = "Opaque"
  
  depends_on = [
    module.aks,
    module.keyvault,
    module.storage,
    module.servicebus,
    module.identity
  ]
}