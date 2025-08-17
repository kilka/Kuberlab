variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "location" {
  description = "Azure region for the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "tenant_id" {
  description = "Azure AD tenant ID for Entra integration"
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Subnet ID for AKS nodes"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for monitoring"
  type        = string
}

# Network Configuration
variable "dns_service_ip" {
  description = "DNS service IP for Kubernetes"
  type        = string
  default     = "10.2.0.10"
}

variable "service_cidr" {
  description = "Service CIDR for Kubernetes services"
  type        = string
  default     = "10.2.0.0/24"
}

# System Node Pool
variable "system_node_count" {
  description = "Initial number of system nodes"
  type        = number
  default     = 1
}

variable "system_node_min_count" {
  description = "Minimum number of system nodes"
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Maximum number of system nodes"
  type        = number
  default     = 3
}

variable "system_node_vm_size" {
  description = "VM size for system nodes"
  type        = string
  default     = "Standard_B2s"
}

# User Node Pool
variable "user_node_count" {
  description = "Initial number of user nodes"
  type        = number
  default     = 0
}

variable "user_node_min_count" {
  description = "Minimum number of user nodes"
  type        = number
  default     = 0
}

variable "user_node_max_count" {
  description = "Maximum number of user nodes"
  type        = number
  default     = 10
}

variable "user_node_vm_size" {
  description = "VM size for user nodes"
  type        = string
  default     = "Standard_B2s"
}

variable "spot_max_price" {
  description = "Maximum price for spot instances (-1 for pay-as-you-go price)"
  type        = number
  default     = -1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}