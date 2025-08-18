#!/bin/bash
# Post-deployment script to ensure everything is ready after fresh terraform apply

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Running post-deployment setup..."

# 1. Get ACR name from Terraform outputs
cd "$PROJECT_ROOT/infra"
ACR_NAME=$(terraform output -raw acr_name 2>/dev/null)
if [ -z "$ACR_NAME" ]; then
    echo "❌ Could not get ACR name from Terraform outputs"
    exit 1
fi

echo "📦 ACR: $ACR_NAME"

# 2. Login to ACR
echo "🔐 Logging into ACR..."
az acr login --name "$ACR_NAME"

# 3. Check if images exist in ACR
echo "🔍 Checking for existing images in ACR..."
API_EXISTS=$(az acr repository show --name "$ACR_NAME" --repository ocr-api 2>/dev/null || echo "")
WORKER_EXISTS=$(az acr repository show --name "$ACR_NAME" --repository ocr-worker 2>/dev/null || echo "")

# 4. Build and push images if they don't exist
if [ -z "$API_EXISTS" ] || [ -z "$WORKER_EXISTS" ]; then
    echo "🏗️ Building and pushing Docker images..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    cd "$PROJECT_ROOT/app"
    
    if [ -z "$API_EXISTS" ]; then
        echo "📦 Building and pushing API image..."
        docker buildx build --platform linux/amd64,linux/arm64 \
            -t "$ACR_NAME.azurecr.io/ocr-api:v1.0.2" \
            --push api/
    fi
    
    if [ -z "$WORKER_EXISTS" ]; then
        echo "📦 Building and pushing Worker image..."
        docker buildx build --platform linux/amd64,linux/arm64 \
            -t "$ACR_NAME.azurecr.io/ocr-worker:v1.0.2" \
            --push worker/
    fi
else
    echo "✅ Images already exist in ACR"
fi

# 5. Wait for Flux to be ready
echo "⏳ Waiting for Flux to be ready..."
cd "$PROJECT_ROOT/infra"
CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
RG=$(terraform output -raw resource_group_name 2>/dev/null)

# Get AKS credentials
echo "🔑 Getting AKS credentials..."
az aks get-credentials --resource-group "$RG" --name "$CLUSTER_NAME" --overwrite-existing --admin

# Wait for Flux system to be ready
echo "⏳ Waiting for Flux system pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=flux -n flux-system --timeout=300s 2>/dev/null || true

# 6. Force Flux to reconcile
echo "🔄 Forcing Flux reconciliation..."
kubectl annotate kustomization infrastructure reconcile.fluxcd.io/requestedAt=$(date +%s) -n flux-system --overwrite
kubectl annotate kustomization controllers reconcile.fluxcd.io/requestedAt=$(date +%s) -n flux-system --overwrite
kubectl annotate kustomization apps reconcile.fluxcd.io/requestedAt=$(date +%s) -n flux-system --overwrite

# 7. Wait for External Secrets Operator
echo "⏳ Waiting for External Secrets Operator..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets-system --timeout=300s 2>/dev/null || true

# 8. Wait for ALB Controller
echo "⏳ Waiting for ALB Controller..."
kubectl wait --for=condition=ready pod -l app=alb-controller -n azure-alb-system --timeout=300s 2>/dev/null || true

# 9. Check if secrets are synced
echo "🔐 Checking secret synchronization..."
for i in {1..30}; do
    SECRET_KEYS=$(kubectl get secret ocr-config -n ocr -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")
    if echo "$SECRET_KEYS" | grep -q "servicebus-connection-string" && echo "$SECRET_KEYS" | grep -q "storage-connection-string"; then
        echo "✅ Secrets are properly synchronized"
        break
    fi
    echo "⏳ Waiting for secrets to sync... ($i/30)"
    sleep 10
done

# 10. Restart deployments to pick up secrets
echo "🔄 Restarting deployments to pick up secrets..."
kubectl rollout restart deploy -n ocr 2>/dev/null || true

# 11. Final status check
echo ""
echo "📊 Final Status Check:"
echo "===================="
kubectl get nodes
echo ""
echo "Flux Status:"
kubectl get kustomizations -n flux-system
echo ""
echo "Application Pods:"
kubectl get pods -n ocr
echo ""
echo "External Secrets:"
kubectl get externalsecret -n ocr

echo ""
echo "Gateway Status:"
kubectl get gateway -n ocr -o wide

# Wait for Gateway to be programmed
echo ""
echo "⏳ Waiting for Gateway to be programmed (this may take a few minutes)..."
for i in {1..30}; do
    GATEWAY_ADDRESS=$(kubectl get gateway ocr-gateway -n ocr -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -n "$GATEWAY_ADDRESS" ]; then
        echo "✅ Gateway is ready at: http://$GATEWAY_ADDRESS"
        echo ""
        echo "Testing API endpoints:"
        curl -s "http://$GATEWAY_ADDRESS/health" && echo "" || echo "API not ready yet"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 10
done

echo ""
echo "✅ Post-deployment setup complete!"
echo ""
if [ -n "$GATEWAY_ADDRESS" ]; then
    echo "🌐 Your OCR API is accessible at: http://$GATEWAY_ADDRESS"
    echo "   - Health: http://$GATEWAY_ADDRESS/health"
    echo "   - Ready:  http://$GATEWAY_ADDRESS/ready"
    echo "   - OCR:    http://$GATEWAY_ADDRESS/ocr (POST with image file)"
else
    echo "⚠️  Gateway is not yet ready. Check status with: kubectl get gateway -n ocr"
fi