output "namespace_id" {
  description = "Service Bus namespace ID"
  value       = azurerm_servicebus_namespace.main.id
}

output "namespace_name" {
  description = "Service Bus namespace name"
  value       = azurerm_servicebus_namespace.main.name
}

output "namespace_primary_connection_string" {
  description = "Primary connection string for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "namespace_secondary_connection_string" {
  description = "Secondary connection string for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_secondary_connection_string
  sensitive   = true
}

output "queue_name" {
  description = "OCR jobs queue name"
  value       = azurerm_servicebus_queue.ocr_jobs.name
}

output "queue_id" {
  description = "OCR jobs queue ID"
  value       = azurerm_servicebus_queue.ocr_jobs.id
}