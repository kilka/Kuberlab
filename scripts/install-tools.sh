#!/bin/bash

# Install required tools for OCR AKS project
echo "Installing Azure CLI, kubectl, and Helm..."

# Install Azure CLI
if ! command -v az &> /dev/null; then
    echo "Installing Azure CLI..."
    brew install azure-cli
else
    echo "Azure CLI already installed"
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    brew install kubectl
else
    echo "kubectl already installed"
fi

# Install Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    brew install helm
else
    echo "Helm already installed"
fi

echo "Verifying installations..."
echo "Azure CLI: $(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo 'Not installed')"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'Not installed')"
echo "Helm: $(helm version --short 2>/dev/null || echo 'Not installed')"
echo "Terraform: $(terraform version | head -1)"

echo ""
echo "Next steps:"
echo "1. Run 'az login' to authenticate with Azure"
echo "2. Run 'az account set --subscription \"Your Subscription\"' if needed"
echo "3. Navigate to infra/ directory and run 'terraform init'"