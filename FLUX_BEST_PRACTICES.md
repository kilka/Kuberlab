# Azure Flux Extension Best Practices for AKS

## Current Implementation (Demo)

This demo uses Azure Flux extension with hardcoded values for simplicity. The SecretStore configuration uses literal values for the Key Vault URL and Tenant ID.

## Production Best Practices

### 1. **Use SOPS for Secret Encryption**
- Encrypt secrets in Git using SOPS with Azure Key Vault
- Flux can decrypt SOPS-encrypted secrets natively
- No secrets stored in plaintext in Git

```yaml
# Example: encrypted secret with SOPS
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
data:
  password: ENC[AES256_GCM,data:...,type:str]
sops:
  kms:
    - arn: arn:aws:kms:...
  azure_kv:
    - name: dev-ocr-kv-001
      key: sops-key
```

### 2. **Use Kustomize Overlays for Environment-Specific Values**
- Create overlays for each environment (dev, staging, prod)
- Use patches to modify base resources

```yaml
# clusters/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: SecretStore
      name: azure-keyvault
    patch: |-
      - op: replace
        path: /spec/provider/azurekv/vaultUrl
        value: https://dev-ocr-kv-001.vault.azure.net
```

### 3. **Azure Key Vault CSI Driver**
- For direct secret mounting without External Secrets Operator
- Secrets mounted as volumes in pods
- Automatic rotation support

```yaml
# Example: SecretProviderClass for CSI Driver
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    keyvaultName: "dev-ocr-kv-001"
    tenantId: "2783cd69-70c6-4d3a-b7e6-8f90e7419ab2"
```

### 4. **External Secrets Operator with Workload Identity**
- Current approach in demo
- Best for dynamic secret management
- Supports secret rotation and multiple providers

### 5. **ConfigMap/Secret Generators in Kustomize**
- Generate ConfigMaps/Secrets from files or literals
- Can be combined with patches for environment-specific values

## Why Azure Flux Extension Doesn't Support PostBuild Substitution

The Azure Flux extension creates Kustomization resources directly via the Azure API, not through Flux's native GitOps workflow. This means:

1. **No postBuild support**: The Azure-managed Kustomizations don't support postBuild.substituteFrom
2. **Limited templating**: Can't use variable substitution like $(VAR_NAME)
3. **Solution**: Use one of the approaches above instead

## Recommended Approach by Scenario

| Scenario | Recommended Approach |
|----------|---------------------|
| **Demo/POC** | Hardcoded values or Kustomize patches |
| **Production with GitOps** | SOPS encryption with Azure Key Vault |
| **High-security environments** | Azure Key Vault CSI Driver |
| **Multi-cloud or complex secrets** | External Secrets Operator |
| **Simple deployments** | Kustomize overlays with patches |

## Implementation Checklist

- [ ] Choose secret management approach based on requirements
- [ ] Configure Azure Key Vault with appropriate access policies
- [ ] Set up Workload Identity for pod authentication
- [ ] Implement secret rotation strategy
- [ ] Configure monitoring and alerting for secret access
- [ ] Document secret recovery procedures
- [ ] Test disaster recovery scenarios

## Security Considerations

1. **Least Privilege**: Grant minimal required permissions
2. **Audit Logging**: Enable Key Vault audit logs
3. **Network Policies**: Restrict secret access to specific pods
4. **Secret Rotation**: Implement automatic rotation where possible
5. **Backup**: Regular backup of Key Vault secrets

## References

- [GitOps for AKS - Microsoft Learn](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gitops-aks/gitops-blueprint-aks)
- [Flux Security - Secrets Management](https://fluxcd.io/flux/security/secrets-management/)
- [External Secrets Operator - Azure Provider](https://external-secrets.io/latest/provider/azure-key-vault/)
- [Azure Key Vault CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)