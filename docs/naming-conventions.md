# Naming Conventions

## Resource Naming

### Format
`{environment}-{project}-{resource-type}-{sequence}`

### Examples
- Resource Group: `dev-ocr-rg-001`
- AKS Cluster: `dev-ocr-aks-001`
- Storage Account: `devocrstg001` (no hyphens, alphanumeric only)
- Key Vault: `dev-ocr-kv-001`

## Tags

All resources must include these tags:

```hcl
tags = {
  Environment = "dev"      # dev, staging, prod
  Project     = "ocr-aks"
  Owner       = "platform-team"
  CostCenter  = "engineering"
  CreatedBy   = "terraform"
}
```

## Kubernetes

### Namespaces
- `ocr` - Application workloads
- `keda-system` - KEDA operator
- `agc-system` - Application Gateway Controller

### Labels
```yaml
labels:
  app.kubernetes.io/name: ocr-api
  app.kubernetes.io/instance: ocr-api-v1
  app.kubernetes.io/version: "1.0.0"
  app.kubernetes.io/component: api
  app.kubernetes.io/part-of: ocr-system
  app.kubernetes.io/managed-by: helm
```