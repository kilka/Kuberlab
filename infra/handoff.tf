# Handoff configuration from Terraform to Flux
# This creates a minimal Secret with non-sensitive configuration values
# that Flux will use for variable substitution via postBuild.substituteFrom

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
resource "kubernetes_secret" "cluster_config" {
  metadata {
    name      = "cluster-config"
    namespace = kubernetes_namespace.ocr.metadata[0].name
  }
  
  data = {
    # Azure resource names for Flux substitution
    KEY_VAULT_NAME              = module.keyvault.vault_name
    STORAGE_ACCOUNT_NAME        = module.storage.account_name
    SERVICE_BUS_NAMESPACE       = module.servicebus.namespace_name
    SERVICE_BUS_QUEUE           = module.servicebus.queue_name
    WORKLOAD_IDENTITY_CLIENT_ID = module.identity.client_id
    TENANT_ID                   = local.tenant_id
    KUBELET_IDENTITY_CLIENT_ID  = module.aks.kubelet_identity.client_id
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