# Azure Consumption Budget for cost control
# This creates a budget with email alerts at different thresholds

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "${local.name_prefix}-budget-monthly"
  subscription_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  amount     = 50
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = timeadd(formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp()), "8760h") # 1 year
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      var.budget_alert_email
    ]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      var.budget_alert_email
    ]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      var.budget_alert_email
    ]
  }

  notification {
    enabled        = true
    threshold      = 120
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      var.budget_alert_email
    ]
  }
}

# Resource group level budget for more granular control
resource "azurerm_consumption_budget_resource_group" "project" {
  name              = "${local.name_prefix}-budget-rg"
  resource_group_id = azurerm_resource_group.main.id

  amount     = 40 # Slightly less than subscription budget
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = timeadd(formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp()), "8760h")
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      var.budget_alert_email
    ]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      var.budget_alert_email
    ]
  }
}