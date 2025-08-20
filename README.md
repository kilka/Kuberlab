# OCR AKS Demo Project

A production-ready OCR API on Azure Kubernetes Service (AKS) demonstrating modern cloud-native patterns, security best practices, and operational excellence.

## Quick Start

### One-Command Deployment

```bash
# Clone and deploy everything
git clone https://github.com/kilka/Kuberlab
cd Kuberlab
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edit infra/terraform.tfvars with your email for budget alerts

# Deploy everything (infrastructure + applications)
make deploy
```

The `make deploy` command automatically:
1. Creates all Azure infrastructure via Terraform
2. Checks if Docker images exist in ACR
3. Builds and pushes missing images automatically
4. Configures GitOps with Flux
5. Verifies deployment success

### Clean Teardown

```bash
# Remove everything (no traces left)
make destroy
```

### Available Commands

```bash
make help           # Show all available commands
make deploy         # Complete deployment (infrastructure + apps)
make destroy        # Fast teardown
make connect        # Connect kubectl to AKS cluster
make pod-status     # Check application pod status
make flux-status    # Check GitOps sync status
make check-images   # Verify Docker images in ACR
make build-images   # Build missing Docker images
make cost           # Check current Azure costs
```

## Architecture

- **Frontend**: Application Gateway for Containers (AGC) with Gateway API
- **Compute**: AKS with AAD RBAC, Workload Identity, Calico NetworkPolicies
- **Application**: FastAPI OCR service + Python workers with Tesseract
- **Messaging**: Azure Service Bus for async job processing
- **Storage**: Blob Storage (images/results) + Table Storage (job metadata)
- **Security**: Key Vault + Workload Identity, Pod Security Standards
- **Scaling**: KEDA for queue-based autoscaling, HPA for API pods
- **Observability**: Container Insights, Log Analytics, custom alerts

## Features

### Seamless Deployment
- **One-command setup**: `make deploy` handles everything
- **Automatic image building**: Missing Docker images are built automatically
- **GitOps with Flux**: All Kubernetes resources managed via Git
- **Clean teardown**: `make destroy` removes everything with no traces

### Production Patterns
- **Workload Identity**: No secrets in code, everything via Azure AD
- **External Secrets Operator**: Secrets pulled from Key Vault at runtime
- **Zero-trust networking**: Calico NetworkPolicies for pod-to-pod security
- **Multi-architecture support**: Docker images built for AMD64 and ARM64

## Cost Target

~$0.70/hr during development, scales to $0 when idle (workers scale to zero)

## Documentation

- [Architecture](docs/architecture.md)
- [Operations Guide](docs/runbook.md)
- [Demo Scenarios](docs/demo-scenarios.md)