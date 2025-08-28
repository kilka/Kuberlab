terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.41"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    # Flux provider for GitOps - using Azure Flux Extension
    # No direct provider needed since we'll use azurerm_kubernetes_flux_configuration
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy                = true
      purge_soft_deleted_secrets_on_destroy      = true
      purge_soft_deleted_keys_on_destroy         = true
      purge_soft_deleted_certificates_on_destroy = true
      recover_soft_deleted_key_vaults            = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
}

provider "azuread" {}

# Kubernetes provider using AKS admin credentials
# This is only used to create the minimal handoff Secret
provider "kubernetes" {
  host                   = module.aks.admin_host
  client_certificate     = base64decode(module.aks.admin_client_certificate)
  client_key             = base64decode(module.aks.admin_client_key)
  cluster_ca_certificate = base64decode(module.aks.admin_cluster_ca_certificate)
}

data "azurerm_client_config" "current" {}

locals {
  client_id       = data.azurerm_client_config.current.client_id
  tenant_id       = data.azurerm_client_config.current.tenant_id
  subscription_id = data.azurerm_client_config.current.subscription_id
}