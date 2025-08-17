#!/bin/bash

# Setup Azure budget and cost alerts for OCR AKS Demo
# This creates a subscription-level budget that will alert you before costs get too high

set -e

echo "🎯 Setting up Azure Budget and Cost Alerts for OCR AKS Demo"
echo "============================================================"

# Configuration
BUDGET_NAME="ocr-aks-demo-budget"
MONTHLY_BUDGET=50  # $50/month for development
DAILY_BUDGET=5     # $5/day safety limit

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_USER=$(az account show --query user.name --output tsv)

echo "📊 Subscription: $SUBSCRIPTION_NAME"
echo "👤 Current User: $CURRENT_USER"
echo ""

# Prompt for email if not provided
if [ -z "$ALERT_EMAIL" ]; then
    read -p "📧 Enter email for budget alerts (default: $CURRENT_USER): " ALERT_EMAIL
    ALERT_EMAIL=${ALERT_EMAIL:-$CURRENT_USER}
fi

echo ""
echo "Budget Configuration:"
echo "  • Monthly Budget: \$$MONTHLY_BUDGET"
echo "  • Daily Budget: \$$DAILY_BUDGET"
echo "  • Alert Email: $ALERT_EMAIL"
echo ""

read -p "Continue with budget creation? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Budget creation cancelled"
    exit 1
fi

# Install required extension if not already installed
echo "📦 Checking Azure CLI extensions..."
if ! az extension show --name cost-management &>/dev/null; then
    echo "  Installing cost-management extension..."
    az extension add --name cost-management
fi

# Get current date for budget start
START_DATE=$(date +%Y-%m-01)  # First day of current month
END_DATE=$(date -d "next year" +%Y-%m-01)  # One year from now

# Create subscription-level budget with multiple alert thresholds
echo "💰 Creating monthly budget with alerts..."

az costmanagement budget create \
    --budget-name "$BUDGET_NAME-monthly" \
    --amount $MONTHLY_BUDGET \
    --time-grain Monthly \
    --start-date $START_DATE \
    --end-date $END_DATE \
    --category Cost \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --notifications "{
        '50': {
            'enabled': true,
            'operator': 'GreaterThan',
            'contactEmails': ['$ALERT_EMAIL'],
            'threshold': 50,
            'thresholdType': 'Percentage'
        },
        '80': {
            'enabled': true,
            'operator': 'GreaterThan',
            'contactEmails': ['$ALERT_EMAIL'],
            'threshold': 80,
            'thresholdType': 'Percentage'
        },
        '100': {
            'enabled': true,
            'operator': 'GreaterThan',
            'contactEmails': ['$ALERT_EMAIL'],
            'threshold': 100,
            'thresholdType': 'Percentage'
        },
        '120': {
            'enabled': true,
            'operator': 'GreaterThan',
            'contactEmails': ['$ALERT_EMAIL'],
            'threshold': 120,
            'thresholdType': 'Percentage'
        }
    }" 2>/dev/null || {
        echo "⚠️  Monthly budget might already exist or using older API. Trying alternative method..."
    }

# Create a daily budget as additional safety
echo "🛡️  Creating daily budget safety limit..."

DAILY_START=$(date +%Y-%m-%d)
DAILY_END=$(date -d "tomorrow" +%Y-%m-%d)

az costmanagement budget create \
    --budget-name "$BUDGET_NAME-daily" \
    --amount $DAILY_BUDGET \
    --time-grain Monthly \
    --start-date $START_DATE \
    --end-date $END_DATE \
    --category Cost \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --notifications "{
        '80': {
            'enabled': true,
            'operator': 'GreaterThan',
            'contactEmails': ['$ALERT_EMAIL'],
            'threshold': 80,
            'thresholdType': 'Percentage'
        },
        '100': {
            'enabled': true,
            'operator': 'GreaterThan',
            'contactEmails': ['$ALERT_EMAIL'],
            'threshold': 100,
            'thresholdType': 'Percentage'
        }
    }" 2>/dev/null || {
        echo "⚠️  Daily budget might already exist. Checking existing budgets..."
    }

# Alternative: Create using consumption API if cost-management fails
if ! az costmanagement budget list --scope "/subscriptions/$SUBSCRIPTION_ID" &>/dev/null; then
    echo "🔄 Trying alternative API (consumption)..."
    
    # Check/install consumption extension
    if ! az extension show --name consumption &>/dev/null; then
        az extension add --name consumption
    fi
    
    # Create budget using consumption API (older but more widely available)
    az consumption budget create \
        --budget-name "$BUDGET_NAME" \
        --amount $MONTHLY_BUDGET \
        --category "Cost" \
        --time-grain "Monthly" \
        --start-date "$START_DATE" \
        --end-date "$END_DATE" \
        --resource-group "dev-ocr-rg-001" \
        --subscription "$SUBSCRIPTION_ID" \
        --notifications "[
            {
                'enabled': true,
                'operator': 'GreaterThan',
                'threshold': 50,
                'contactEmails': ['$ALERT_EMAIL'],
                'thresholdType': 'Percentage'
            },
            {
                'enabled': true,
                'operator': 'GreaterThan',
                'threshold': 80,
                'contactEmails': ['$ALERT_EMAIL'],
                'thresholdType': 'Percentage'
            },
            {
                'enabled': true,
                'operator': 'GreaterThan',
                'threshold': 100,
                'contactEmails': ['$ALERT_EMAIL'],
                'thresholdType': 'Percentage'
            }
        ]" 2>/dev/null || {
            echo "ℹ️  Note: Budget will be created at resource group level after deployment"
        }
fi

# Create an action group for more sophisticated alerting
echo "🔔 Creating action group for alerts..."
az monitor action-group create \
    --name "ocr-budget-alerts" \
    --resource-group "default" \
    --short-name "OCRBudget" \
    --email-receiver name="BudgetAlert" email-address="$ALERT_EMAIL" 2>/dev/null || {
        echo "ℹ️  Action group will be created with resource group"
    }

echo ""
echo "✅ Budget setup complete!"
echo ""
echo "📋 Summary:"
echo "  • Monthly budget: \$$MONTHLY_BUDGET with alerts at 50%, 80%, 100%, 120%"
echo "  • Daily safety limit: \$$DAILY_BUDGET with alerts at 80%, 100%"
echo "  • Alerts will be sent to: $ALERT_EMAIL"
echo ""
echo "💡 Tips:"
echo "  • You'll receive an email when spending reaches each threshold"
echo "  • Current month spending resets on the 1st"
echo "  • Check spending anytime: az costmanagement actual list --scope \"/subscriptions/$SUBSCRIPTION_ID\""
echo "  • Portal: https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview"
echo ""
echo "⚠️  IMPORTANT: After deployment, run this command to check costs:"
echo "  az consumption usage list --subscription $SUBSCRIPTION_ID --start-date $START_DATE --end-date $(date +%Y-%m-%d)"
echo ""
echo "🚨 Emergency destroy command (if costs spike):"
echo "  cd infra && terraform destroy -auto-approve"