# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law-${var.sequence}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

# Container Insights solution (for AKS monitoring)
resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  tags = var.tags
}

# Data Collection Rule for Container Insights
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "${var.name_prefix}-dcr-${var.sequence}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "destination-log"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["destination-log"]
  }

  data_sources {
    extension {
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        "dataCollectionSettings" = {
          "interval"                    = "1m"
          "namespaceFilteringMode"      = "Off"
          "namespaces"                  = ["kube-system", "gatekeeper-system", "azure-arc"]
          "enableContainerLogV2"        = true
        }
      })
      name = "ContainerInsightsExtension"
    }
  }

  description = "Data Collection Rule for Container Insights"
}