#!/bin/bash

# Setup Azure budget and cost alerts
# Run this after deploying the resource group

RESOURCE_GROUP="dev-ocr-rg-001"
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Create budget (requires az consumption extension)
az extension add --name consumption

# Create $50/month budget with 80% and 100% alerts
az consumption budget create \
  --budget-name "ocr-demo-budget" \
  --amount 50 \
  --category "Cost" \
  --time-grain "Monthly" \
  --time-period-start-date "2024-01-01" \
  --resource-group $RESOURCE_GROUP \
  --notifications '[
    {
      "enabled": true,
      "operator": "GreaterThan",
      "threshold": 80,
      "contactEmails": ["your-email@domain.com"],
      "contactRoles": [],
      "contactGroups": [],
      "thresholdType": "Percentage"
    },
    {
      "enabled": true,
      "operator": "GreaterThan", 
      "threshold": 100,
      "contactEmails": ["your-email@domain.com"],
      "contactRoles": [],
      "contactGroups": [],
      "thresholdType": "Percentage"
    }
  ]'

echo "Budget created. Update email address in script before running."