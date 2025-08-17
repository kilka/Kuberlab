output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "AKS cluster FQDN"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kubelet_identity" {
  description = "AKS kubelet identity"
  value = {
    client_id                 = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
    object_id                 = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
    user_assigned_identity_id = azurerm_kubernetes_cluster.main.kubelet_identity[0].user_assigned_identity_id
  }
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "cluster_ca_certificate" {
  description = "AKS cluster CA certificate"
  value       = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  sensitive   = true
}

output "host" {
  description = "AKS cluster host"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.host
  sensitive   = true
}

output "client_certificate" {
  description = "AKS cluster client certificate"
  value       = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  sensitive   = true
}

output "client_key" {
  description = "AKS cluster client key"
  value       = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  sensitive   = true
}

output "kube_config_raw" {
  description = "Raw kubeconfig"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kube_config" {
  description = "Structured kube config for provider configuration"
  value = {
    host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
    username               = azurerm_kubernetes_cluster.main.kube_config.0.username
    password               = azurerm_kubernetes_cluster.main.kube_config.0.password
    client_certificate     = azurerm_kubernetes_cluster.main.kube_config.0.client_certificate
    client_key            = azurerm_kubernetes_cluster.main.kube_config.0.client_key
    cluster_ca_certificate = azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate
  }
  sensitive = true
}

# Admin credentials for the handoff Secret only
output "admin_host" {
  description = "Kubernetes API server host"
  value       = azurerm_kubernetes_cluster.main.kube_admin_config[0].host
  sensitive   = true
}

output "admin_client_certificate" {
  description = "Client certificate for admin access"
  value       = azurerm_kubernetes_cluster.main.kube_admin_config[0].client_certificate
  sensitive   = true
}

output "admin_client_key" {
  description = "Client key for admin access"
  value       = azurerm_kubernetes_cluster.main.kube_admin_config[0].client_key
  sensitive   = true
}

output "admin_cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = azurerm_kubernetes_cluster.main.kube_admin_config[0].cluster_ca_certificate
  sensitive   = true
}