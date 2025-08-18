#!/bin/bash
# Post-deployment verification script
# Shows status and provides connection info after deployment

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔍 Post-deployment verification..."
echo ""

# Get terraform outputs
cd "$PROJECT_ROOT/infra"
CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
RG=$(terraform output -raw resource_group_name 2>/dev/null)

# Get AKS credentials for kubectl
echo "🔑 Configuring kubectl access..."
az aks get-credentials --resource-group "$RG" --name "$CLUSTER_NAME" --overwrite-existing --admin

# Wait briefly for pods to stabilize
echo "⏳ Waiting for pods to be ready..."
sleep 10

# Check pod status
echo ""
echo "📊 Cluster Status:"
echo "=================="
echo ""
echo "Nodes:"
kubectl get nodes
echo ""

echo "Application Pods:"
kubectl get pods -n ocr 2>/dev/null || echo "No pods found yet"
echo ""

# Check if pods are ready
API_READY=$(kubectl get pods -n ocr -l app=ocr-api -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
WORKER_READY=$(kubectl get pods -n ocr -l app=ocr-worker -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

if [ "$API_READY" != "True" ] || [ "$WORKER_READY" != "True" ]; then
    echo "⏳ Waiting for pods to become ready (up to 2 minutes)..."
    kubectl wait --for=condition=ready pod -l app=ocr-api -n ocr --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=ocr-worker -n ocr --timeout=120s 2>/dev/null || true
    echo ""
    kubectl get pods -n ocr
fi

echo ""
echo "External Secrets:"
kubectl get externalsecret -n ocr 2>/dev/null || echo "No external secrets found"
echo ""

echo "Gateway Status:"
kubectl get gateway -n ocr -o wide 2>/dev/null || echo "No gateway found"

# Get Gateway URL
echo ""
echo "🌐 Getting application URL..."
GATEWAY_ADDRESS=""
for i in {1..30}; do
    GATEWAY_ADDRESS=$(kubectl get gateway ocr-gateway -n ocr -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -n "$GATEWAY_ADDRESS" ]; then
        break
    fi
    if [ $i -eq 1 ]; then
        echo "  Waiting for Gateway to be programmed (this may take a few minutes)..."
    fi
    sleep 5
done

if [ -n "$GATEWAY_ADDRESS" ]; then
    echo ""
    echo "✅ Your OCR API is ready!"
    echo ""
    echo "🌐 API Endpoints:"
    echo "  Base URL: http://$GATEWAY_ADDRESS"
    echo "  Health:   http://$GATEWAY_ADDRESS/health"
    echo "  Ready:    http://$GATEWAY_ADDRESS/ready"  
    echo "  OCR:      http://$GATEWAY_ADDRESS/ocr (POST with image file)"
    echo ""
    
    # Test health endpoint
    echo "🧪 Testing health endpoint..."
    if curl -s -f "http://$GATEWAY_ADDRESS/health" > /dev/null 2>&1; then
        echo "✅ API is responding!"
    else
        echo "⚠️  API is not responding yet. It may need a few more moments to initialize."
    fi
else
    echo "⚠️  Gateway is not ready yet. Check status with:"
    echo "  kubectl get gateway -n ocr"
fi

echo ""
echo "📝 Useful commands:"
echo "  kubectl get pods -n ocr          # Check pod status"
echo "  kubectl logs -f deploy/ocr-api -n ocr     # View API logs"
echo "  kubectl logs -f deploy/ocr-worker -n ocr  # View worker logs"
echo ""