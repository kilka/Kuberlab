variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "sequence" {
  description = "Sequence number for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "retention_in_days" {
  description = "Retention period for logs in days"
  type        = number
  default     = 30
}