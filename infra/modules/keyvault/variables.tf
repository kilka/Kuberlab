variable "key_vault_name" {
  description = "Name of the Key Vault (must be globally unique, 3-24 characters)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

variable "managed_identity_principal_id" {
  description = "Principal ID of managed identity to grant access to Key Vault"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Configuration values to store as secrets
variable "storage_account_name" {
  description = "Storage account name to store in Key Vault"
  type        = string
}

variable "service_bus_namespace" {
  description = "Service Bus namespace to store in Key Vault"
  type        = string
}

variable "service_bus_queue" {
  description = "Service Bus queue name to store in Key Vault"
  type        = string
}