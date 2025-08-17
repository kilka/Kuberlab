variable "server_name" {
  description = "Name of the PostgreSQL server"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "admin_username" {
  description = "Administrator username"
  type        = string
  default     = "ocradmin"
}

variable "sku_name" {
  description = "SKU name for PostgreSQL server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 32768 # 32GB
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "subnet_id" {
  description = "Subnet ID for PostgreSQL delegation"
  type        = string
}

variable "virtual_network_id" {
  description = "Virtual Network ID for private DNS zone linking"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}