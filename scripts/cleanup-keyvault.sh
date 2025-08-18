#!/bin/bash
# Cleanup soft-deleted Key Vaults from current subscription
# This handles cases where Terraform doesn't fully purge

set -e

echo "🔍 Checking for soft-deleted Key Vaults..."

# Get all soft-deleted vaults in the current subscription (with timeout to prevent hanging)
DELETED_VAULTS=$(timeout 10s az keyvault list-deleted --query "[?contains(name, 'ocr')].name" -o tsv 2>/dev/null || echo "")

if [ -z "$DELETED_VAULTS" ]; then
    echo "✅ No soft-deleted Key Vaults found"
    exit 0
fi

echo "⚠️  Found soft-deleted Key Vaults:"
echo "$DELETED_VAULTS" | while read -r vault; do
    echo "  - $vault"
done
echo ""

# Ask for confirmation
read -p "Do you want to permanently purge these vaults? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Purge cancelled"
    exit 1
fi

# Purge each vault
echo "$DELETED_VAULTS" | while read -r vault; do
    if [ -n "$vault" ]; then
        echo "🗑️  Purging Key Vault: $vault"
        az keyvault purge --name "$vault" --no-wait 2>/dev/null || true
    fi
done

echo ""
echo "✅ Key Vault purge initiated. This may take a few moments to complete."
echo "   Note: Purge operations run asynchronously in the background."