variable "identity_name" {
  description = "Name of the user-assigned managed identity"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' for OIDC federation"
  type        = string
}

variable "service_bus_namespace_id" {
  description = "Service Bus namespace ID for role assignments"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account ID for role assignments"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}