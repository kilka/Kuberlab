# Azure Prerequisites Setup

## Required Tools

### 1. Azure CLI
```bash
# Install Azure CLI (macOS)
brew install azure-cli

# Verify installation
az version

# Login to Azure
az login

# Set default subscription (if you have multiple)
az account list --output table
az account set --subscription "Your Subscription Name"

# Verify current context
az account show
```

### 2. Terraform
```bash
# Install via Homebrew (macOS)
brew install terraform

# Or use asdf/tool-versions (recommended for version consistency)
asdf install terraform 1.9.5
asdf global terraform 1.9.5

# Verify installation
terraform version
```

### 3. kubectl
```bash
# Install kubectl
brew install kubectl

# Or via asdf
asdf install kubectl 1.30.3
asdf global kubectl 1.30.3

# Verify installation
kubectl version --client
```

### 4. Helm
```bash
# Install Helm
brew install helm

# Or via asdf
asdf install helm 3.15.3
asdf global helm 3.15.3

# Verify installation
helm version
```

## Azure Configuration

### 1. Check Current Azure Context
```bash
# View current subscription and tenant
az account show --output table

# List all available subscriptions
az account list --output table

# Check current user permissions
az ad signed-in-user show --query '{displayName:displayName, userPrincipalName:userPrincipalName}'
```

### 2. Required Azure Permissions
Your account needs these permissions to deploy the infrastructure:

**Subscription Level:**
- `Contributor` - To create/modify resources
- `User Access Administrator` - To assign RBAC roles

**Azure AD (if creating service principals):**
- `Application Administrator` or `Cloud Application Administrator`

```bash
# Check your role assignments
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --output table
```

### 3. Resource Provider Registration
Register required Azure resource providers:

```bash
# Register required providers
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.ServiceBus
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.ServiceNetworking

# Check registration status
az provider list --query "[?contains(['Microsoft.ContainerService', 'Microsoft.ContainerRegistry', 'Microsoft.KeyVault', 'Microsoft.Storage', 'Microsoft.DBforPostgreSQL', 'Microsoft.ServiceBus'], namespace)].{Namespace:namespace, State:registrationState}" --output table
```

## Terraform Setup

### 1. Initialize Terraform
```bash
cd infra

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
# environment  = "dev"
# project_name = "ocr"
# location     = "East US 2"
# sequence     = "001"

# Initialize Terraform
terraform init
```

### 2. Optional: Configure Remote State
For production, consider using Azure Storage for remote state:

```bash
# Create storage account for Terraform state (optional)
az group create --name "tfstate-rg" --location "East US 2"
az storage account create --name "youruniquetfstate" --resource-group "tfstate-rg" --location "East US 2" --sku "Standard_LRS"
az storage container create --name "tfstate" --account-name "youruniquetfstate"
```

Then add to `providers.tf`:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "youruniquetfstate"
    container_name       = "tfstate"
    key                  = "ocr-aks.tfstate"
  }
}
```

## Validation Commands

### 1. Test Azure Access
```bash
# Test resource group creation
az group create --name "test-permissions-rg" --location "East US 2"
az group delete --name "test-permissions-rg" --yes --no-wait
```

### 2. Test Terraform Plan
```bash
cd infra
terraform plan
```

### 3. Check Tool Versions
```bash
# Verify all tools are correct versions
terraform version
az version
kubectl version --client
helm version
```

## Common Issues & Solutions

### Issue: "Insufficient privileges to complete the operation"
**Solution:** Ensure you have `Contributor` + `User Access Administrator` roles

### Issue: "The subscription is not registered to use namespace"
**Solution:** Run the provider registration commands above

### Issue: "terraform: command not found"
**Solution:** Install Terraform or ensure it's in your PATH

### Issue: "Authentication failed"
**Solution:** Run `az login` again or check `az account show`

## Next Steps

Once prerequisites are complete:
1. Customize `terraform.tfvars` with your values
2. Run `terraform plan` to validate configuration
3. Deploy with `terraform apply`