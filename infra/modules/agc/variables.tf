variable "gateway_name" {
  description = "Name of the Application Gateway for Containers"
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

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for AGC association (must have Microsoft.ServiceNetworking/trafficControllers delegation)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}