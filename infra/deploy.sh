#!/bin/bash
set -e

echo "🚀 Starting OCR AKS Infrastructure Deployment"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    print_error "Not in the infra directory. Please run from infra/"
    exit 1
fi

# Clean up any stale state
if [ -f "terraform.tfstate" ]; then
    print_warning "Found existing state file. Backing up..."
    cp terraform.tfstate "terraform.tfstate.backup.$(date +%s)"
fi

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init -upgrade

# Format check
print_status "Checking Terraform formatting..."
terraform fmt -recursive

# Validate configuration
print_status "Validating Terraform configuration..."
terraform validate

# Plan with reduced parallelism for stability
print_status "Planning infrastructure deployment..."
terraform plan -out=tfplan -parallelism=5

# Apply with reduced parallelism
print_status "Applying infrastructure (this may take 10-15 minutes)..."
terraform apply -parallelism=5 tfplan

# Show outputs
print_status "Deployment complete! Here are your outputs:"
terraform output

echo ""
echo "============================================"
echo "🎉 Infrastructure deployment successful!"
echo ""
echo "Next steps:"
echo "1. Configure kubectl: az aks get-credentials --resource-group dev-ocr-rg-001 --name dev-ocr-aks-001"
echo "2. Install AGC controller: helm install alb-controller ..."
echo "3. Deploy applications to the cluster"