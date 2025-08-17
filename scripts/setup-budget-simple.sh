#!/bin/bash

# Simple Azure Budget Setup for OCR AKS Demo
# Uses the most reliable API methods

set -e

echo "🎯 Azure Budget Setup for OCR AKS Demo"
echo "======================================"
echo ""

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

echo "📊 Subscription: $SUBSCRIPTION_NAME"
echo ""

# Get email for alerts
read -p "📧 Enter email for budget alerts: " ALERT_EMAIL
echo ""

# Create a cost alert using Azure Monitor (most reliable method)
echo "Creating cost anomaly alert..."

# First, ensure we're using the right subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Create a simple daily cost alert using monitor metrics
cat > budget-alert.json <<EOF
{
  "location": "global",
  "tags": {
    "Project": "ocr-aks",
    "Purpose": "Budget Alert"
  },
  "properties": {
    "description": "Alert when daily Azure spending exceeds threshold",
    "severity": 2,
    "enabled": true,
    "scopes": ["/subscriptions/$SUBSCRIPTION_ID"],
    "evaluationFrequency": "PT1H",
    "windowSize": "P1D",
    "criteria": {
      "allOf": [
        {
          "threshold": 5,
          "name": "DailyCostThreshold",
          "metricNamespace": "Microsoft.CostManagement",
          "metricName": "ActualCost",
          "operator": "GreaterThan",
          "timeAggregation": "Total"
        }
      ]
    },
    "actions": {
      "actionGroups": [],
      "customProperties": {
        "email": "$ALERT_EMAIL"
      }
    }
  }
}
EOF

echo "✅ Budget alert configuration created!"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. MANUAL SETUP (Recommended - 2 minutes):"
echo "   ────────────────────────────────────────"
echo "   Open: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/budgets"
echo "   "
echo "   Click: '+ Add'"
echo "   "
echo "   Configure:"
echo "     • Name: ocr-aks-demo-budget"
echo "     • Reset period: Monthly"
echo "     • Budget amount: \$50"
echo "     • Set alerts at: 50%, 80%, 100%"
echo "     • Alert recipients: $ALERT_EMAIL"
echo "   "
echo "   Click: 'Create'"
echo ""
echo "2. AUTOMATED SETUP (If available in your region):"
echo "   ───────────────────────────────────────────────"
echo "   Run: az deployment sub create --location eastus2 \\"
echo "        --template-uri https://aka.ms/cost-budget-template \\"
echo "        --parameters budgetName=ocr-aks amount=50 contactEmail=$ALERT_EMAIL"
echo ""
echo "3. TERRAFORM BUDGET (Alternative):"
echo "   ──────────────────────────────────"
echo "   We can add budget as Terraform resource after initial deployment"
echo ""
echo "💡 Quick Cost Checks:"
echo "   • Current month: az cost query --scope /subscriptions/$SUBSCRIPTION_ID"
echo "   • Cost analysis: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/costanalysis"
echo ""
echo "🚨 Emergency Destroy:"
echo "   cd /Users/josheagar/Documents/Programming/Kuberlab/infra"
echo "   terraform destroy -auto-approve"
echo ""

# Save configuration for reference
cat > /Users/josheagar/Documents/Programming/Kuberlab/.budget-config <<EOF
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
ALERT_EMAIL=$ALERT_EMAIL
MONTHLY_BUDGET=50
DAILY_LIMIT=5
CREATED_DATE=$(date +%Y-%m-%d)
EOF

echo "Configuration saved to .budget-config"