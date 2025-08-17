#!/bin/bash
# Script to clean up stuck Flux resources during terraform destroy

set -e

echo "Cleaning up Flux resources..."

# Get cluster and resource group names from terraform
CLUSTER_NAME=$(terraform -chdir=../infra output -raw aks_cluster_name 2>/dev/null || echo "aks-ocr-demo")
RESOURCE_GROUP=$(terraform -chdir=../infra output -raw resource_group_name 2>/dev/null || echo "rg-ocr-demo")

echo "Cluster: $CLUSTER_NAME"
echo "Resource Group: $RESOURCE_GROUP"

# Try to delete Flux configuration with timeout
echo "Attempting to delete Flux configuration..."
timeout 30s az k8s-configuration flux delete \
  --name flux-system \
  --cluster-name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-type managedClusters \
  --yes --force 2>/dev/null || true

# Try to delete Flux extension
echo "Attempting to delete Flux extension..."
timeout 30s az k8s-extension delete \
  --name flux \
  --cluster-name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-type managedClusters \
  --yes --force 2>/dev/null || true

# Remove from Terraform state if still stuck
echo "Checking Terraform state..."
cd ../infra
if terraform state list | grep -q "azurerm_kubernetes_flux_configuration.main"; then
  echo "Removing Flux configuration from state..."
  terraform state rm azurerm_kubernetes_flux_configuration.main
fi

if terraform state list | grep -q "azurerm_kubernetes_cluster_extension.flux"; then
  echo "Removing Flux extension from state..."
  terraform state rm azurerm_kubernetes_cluster_extension.flux
fi

echo "Flux cleanup complete. You can now run 'terraform destroy' again."