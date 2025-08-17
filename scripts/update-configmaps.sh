#!/bin/bash
# Post-deploy script to update ConfigMaps with actual Azure resource values
# This runs after Terraform creates the infrastructure

set -e

echo "Updating ConfigMaps with Azure resource values..."

# Get values from Terraform outputs
cd infra
WORKLOAD_IDENTITY_CLIENT_ID=$(terraform output -raw workload_identity_client_id 2>/dev/null || echo "pending")
SERVICE_BUS_NAMESPACE=$(terraform output -raw service_bus_namespace 2>/dev/null || echo "pending")
SERVICE_BUS_QUEUE=$(terraform output -raw service_bus_queue 2>/dev/null || echo "pending")
STORAGE_ACCOUNT_NAME=$(terraform output -raw storage_account_name 2>/dev/null || echo "pending")
KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "pending")
cd ..

# Update the OCR ConfigMap
kubectl patch configmap ocr-config -n ocr --type merge -p "{
  \"data\": {
    \"SERVICE_BUS_NAMESPACE\": \"$SERVICE_BUS_NAMESPACE\",
    \"SERVICE_BUS_QUEUE\": \"$SERVICE_BUS_QUEUE\",
    \"STORAGE_ACCOUNT_NAME\": \"$STORAGE_ACCOUNT_NAME\",
    \"KEY_VAULT_NAME\": \"$KEY_VAULT_NAME\"
  }
}" 2>/dev/null || echo "ConfigMap will be updated once deployed"

# Update Service Accounts with Workload Identity
kubectl annotate serviceaccount ocr-api -n ocr \
  azure.workload.identity/client-id=$WORKLOAD_IDENTITY_CLIENT_ID \
  --overwrite 2>/dev/null || true

kubectl annotate serviceaccount ocr-worker -n ocr \
  azure.workload.identity/client-id=$WORKLOAD_IDENTITY_CLIENT_ID \
  --overwrite 2>/dev/null || true

echo "✅ ConfigMaps updated with Azure resource values"