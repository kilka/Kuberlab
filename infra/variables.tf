variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ocr"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
}

variable "sequence" {
  description = "Sequence number for resource naming"
  type        = string
  default     = "001"
}

variable "admin_group_object_id" {
  description = "Azure AD group object ID for AKS admin access"
  type        = string
  default     = null
}

variable "github_repository" {
  description = "GitHub repository for OIDC federation (format: owner/repo)"
  type        = string
  default     = null
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Resource owner"
  type        = string
  default     = "platform-team"
}

locals {
  # Common naming convention
  name_prefix = "${var.environment}-${var.project_name}"
  
  # Common tags applied to all resources
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Owner       = var.owner
    CostCenter  = var.cost_center
    CreatedBy   = "terraform"
    Repository  = var.github_repository
  }

  # Storage account name (must be globally unique, alphanumeric only)
  storage_account_name = "${var.environment}${var.project_name}stg${var.sequence}"
}