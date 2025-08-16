# OCR AKS Demo Project

A production-ready OCR API on Azure Kubernetes Service (AKS) demonstrating modern cloud-native patterns, security best practices, and operational excellence.

## Quick Start

```bash
# Deploy infrastructure
cd infra
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Deploy applications
kubectl apply -k k8s/manifests
```

## Architecture

- **Frontend**: Application Gateway for Containers (AGC) with Gateway API
- **Compute**: AKS with AAD RBAC, Workload Identity, Calico NetworkPolicies
- **Application**: FastAPI OCR service + Python workers with Tesseract
- **Messaging**: Azure Service Bus for async job processing
- **Storage**: Blob Storage (images/results) + PostgreSQL (job metadata)
- **Security**: Key Vault + Workload Identity, Pod Security Standards
- **Scaling**: KEDA for queue-based autoscaling, HPA for API pods
- **Observability**: Container Insights, Log Analytics, custom alerts

## Cost Target

~$1.50/hr during development, scales to $0 when idle (workers scale to zero)

## Documentation

- [Architecture](docs/architecture.md)
- [Operations Guide](docs/runbook.md)
- [Demo Scenarios](docs/demo-scenarios.md)