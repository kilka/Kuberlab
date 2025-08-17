variable "namespace_name" {
  description = "Name of the Service Bus namespace"
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

variable "sku" {
  description = "Service Bus namespace SKU"
  type        = string
  default     = "Basic"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium."
  }
}

variable "capacity" {
  description = "Service Bus namespace capacity (only for Premium SKU)"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}