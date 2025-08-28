# Handoff configuration from Terraform to Flux
# This creates a minimal Secret with non-sensitive configuration values
# that Flux will use for variable substitution via postBuild.substituteFrom
# Using null_resource with local-exec to avoid Kubernetes provider issues during initial apply

# Create a temporary kubeconfig for applying the handoff secret
resource "local_file" "kubeconfig" {
  content = <<-KUBECONFIG
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority-data: ${module.aks.admin_cluster_ca_certificate}
        server: ${module.aks.admin_host}
      name: cluster
    contexts:
    - context:
        cluster: cluster
        user: user
      name: default
    current-context: default
    users:
    - name: user
      user:
        client-certificate-data: ${module.aks.admin_client_certificate}
        client-key-data: ${module.aks.admin_client_key}
  KUBECONFIG
  
  filename = "${path.module}/.kube-config"
  
  depends_on = [module.aks]
}

# Apply handoff secret using kubectl
resource "null_resource" "create_handoff_secret" {
  triggers = {
    # Recreate if any of these values change
    cluster_endpoint     = module.aks.admin_host
    key_vault_name      = module.keyvault.vault_name
    storage_account     = module.storage.account_name
    servicebus_name     = module.servicebus.namespace_name
    api_identity        = module.identity.api_client_id
    worker_identity     = module.identity.worker_client_id
    github_identity     = module.identity.github_client_id
  }
  
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_file.kubeconfig.filename
    }
    
    command = <<-EOT
      # Wait for cluster to be ready
      timeout 300 bash -c 'until kubectl get nodes; do sleep 10; done'
      
      # Create flux-system namespace if it doesn't exist
      kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
      
      # Create the handoff secret in flux-system namespace
      kubectl create secret generic cluster-config \
        --namespace=flux-system \
        --from-literal=KEY_VAULT_NAME="${module.keyvault.vault_name}" \
        --from-literal=STORAGE_ACCOUNT_NAME="${module.storage.account_name}" \
        --from-literal=SERVICE_BUS_NAMESPACE="${module.servicebus.namespace_name}" \
        --from-literal=SERVICE_BUS_QUEUE="${module.servicebus.queue_name}" \
        --from-literal=SERVICE_BUS_POISON_QUEUE="${module.servicebus.poison_queue_name}" \
        --from-literal=API_IDENTITY_CLIENT_ID="${module.identity.api_client_id}" \
        --from-literal=WORKER_IDENTITY_CLIENT_ID="${module.identity.worker_client_id}" \
        --from-literal=GITHUB_IDENTITY_CLIENT_ID="${module.identity.github_client_id}" \
        --from-literal=TENANT_ID="${local.tenant_id}" \
        --from-literal=KUBELET_IDENTITY_CLIENT_ID="${module.aks.kubelet_identity.client_id}" \
        --from-literal=ACR_NAME="${module.acr.name}" \
        --from-literal=AZURE_SUBSCRIPTION_ID="${data.azurerm_client_config.current.subscription_id}" \
        --from-literal=RESOURCE_GROUP="${azurerm_resource_group.main.name}" \
        --from-literal=AGC_NAME="${module.agc.gateway_name}" \
        --from-literal=AGC_FRONTEND_NAME="dev-ocr-frontend" \
        --from-literal=ALB_IDENTITY_CLIENT_ID="${module.identity.alb_client_id}" \
        --from-literal=WORKLOAD_IDENTITY_CLIENT_ID="${module.identity.github_client_id}" \
        --dry-run=client -o yaml | kubectl apply -f -
      
      echo "Handoff secret created successfully"
    EOT
  }
  
  depends_on = [
    module.aks,
    module.keyvault,
    module.storage,
    module.servicebus,
    module.identity,
    module.agc,
    local_file.kubeconfig,
    null_resource.build_docker_images  # Ensure images are ready
  ]
}

# Clean up kubeconfig file
resource "null_resource" "cleanup_kubeconfig" {
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/.kube-config"
  }
  
  depends_on = [null_resource.create_handoff_secret]
}