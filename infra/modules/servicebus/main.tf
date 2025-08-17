resource "azurerm_servicebus_namespace" "main" {
  name                = var.namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  capacity            = var.capacity

  tags = var.tags
}

resource "azurerm_servicebus_queue" "ocr_jobs" {
  name         = "ocr-jobs"
  namespace_id = azurerm_servicebus_namespace.main.id

  # Queue configuration for OCR job processing
  max_size_in_megabytes                = 1024
  default_message_ttl                  = "PT10M" # 10 minutes
  lock_duration                        = "PT30S" # 30 seconds
  max_delivery_count                   = 3
  dead_lettering_on_message_expiration = true

  # Note: Duplicate detection requires Standard tier
  # Using Basic tier for cost optimization
  
  # Enable sessions for message ordering if needed
  requires_session = false
}