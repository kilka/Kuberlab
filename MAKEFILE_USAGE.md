# Makefile Usage Guide

## Quick Start

The Makefile provides a complete automation framework for deploying and managing the OCR AKS infrastructure.

### Prerequisites
1. **Update email for budget alerts**:
   ```bash
   vi infra/terraform.tfvars
   # Change: budget_alert_email = "your-actual-email@example.com"
   ```

2. **Verify prerequisites**:
   ```bash
   make safety-check
   ```

## Primary Commands

### 🚀 Full Deployment
```bash
make deploy
```
This runs the complete deployment pipeline:
- Initializes Terraform
- Runs linters (tflint, checkov)
- Creates and reviews plan
- Prompts for confirmation
- Deploys infrastructure (~40 resources)
- Runs basic tests
- Shows outputs

### 🗑️ Destroy Infrastructure
```bash
make destroy
```
Safely destroys all infrastructure with confirmation.

**Emergency destroy** (no confirmation):
```bash
make destroy-force
# or
make emergency-stop
```

## Step-by-Step Commands

### 1. Initialize
```bash
make init        # Initialize Terraform
```

### 2. Validate & Lint
```bash
make validate    # Validate configuration
make lint        # Run linters
```

### 3. Plan
```bash
make plan        # Create deployment plan
```

### 4. Apply
```bash
make apply       # Apply existing plan
```

### 5. Test
```bash
make test        # Run all tests
make test-basic  # Basic resource checks
make test-connectivity  # AKS connectivity
make test-security     # Security validation
make test-cost        # Check current costs
```

## Utility Commands

### Get AKS Credentials
```bash
make kubeconfig
```

### Show Terraform Outputs
```bash
make show-outputs
```

### Check Costs
```bash
make cost-check
```

### Port Forwarding
```bash
make port-forward SERVICE=my-service PORT=8080
```

### View Logs
```bash
make logs
```

## Cost Control

- **Deployment Cost**: ~$0.60-0.70/hour
- **Budget Alerts**: Configured at 50%, 80%, 100%, 120% of $50/month
- **Scale to Zero**: User nodes scale down when not in use

## Important Notes

1. **Always run `make destroy` when done** to avoid unnecessary costs
2. **Budget alerts** are automatically created with the infrastructure
3. **Emergency destroy** command available if costs spike unexpectedly
4. **All resources are tagged** for cost tracking

## Workflow Examples

### Development Workflow
```bash
# Start fresh
make clean
make deploy

# Work with the cluster
make kubeconfig
kubectl get nodes

# Check costs periodically
make cost-check

# Clean up when done
make destroy
```

### Quick Testing
```bash
# Deploy without full checks
make quick-deploy

# Destroy without prompts
make quick-destroy
```

### Troubleshooting
```bash
# Check what's deployed
make show-outputs

# View cluster logs
make logs

# Run safety checks
make safety-check

# Validate individual modules
make validate-modules
```

## Color Coding
- 🔵 **Blue**: Information/Progress
- 🟢 **Green**: Success
- 🟡 **Yellow**: Warning/Cost Info
- 🔴 **Red**: Error/Danger

## Files Created
- `infra/tfplan` - Terraform plan file
- `infra/plan.log` - Plan output log
- `infra/.terraform/` - Terraform state directory
- `infra/.terraform.lock.hcl` - Provider lock file

## Clean Up
```bash
make clean  # Remove local files (not infrastructure)
```