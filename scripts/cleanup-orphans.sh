#!/bin/bash

# Script to clean up orphaned Azure resources that may persist after terraform destroy
# These are resources that live outside the resource group or may not be properly cleaned

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Checking for orphaned Azure resources...${NC}"

# Get subscription ID
SUBSCRIPTION=$(az account show --query id -o tsv)
echo "Working in subscription: $SUBSCRIPTION"

# Clean up subscription-level budgets
echo -e "\n${YELLOW}Checking for orphaned budgets...${NC}"
BUDGETS=$(az consumption budget list --query "[?name=='dev-ocr-budget-monthly'].name" -o tsv 2>/dev/null || echo "")
if [ -n "$BUDGETS" ]; then
    echo "Found subscription budget: $BUDGETS"
    echo "Deleting..."
    az consumption budget delete --budget-name "dev-ocr-budget-monthly" 2>/dev/null || true
    echo -e "${GREEN}✓ Deleted${NC}"
else
    echo "No orphaned subscription budgets found"
fi

# Check for existing Key Vaults with old secrets
echo -e "\n${YELLOW}Checking for existing Key Vaults with old secrets...${NC}"
EXISTING_KVS=$(az keyvault list --query "[?contains(name, 'dev-ocr-kv')].name" -o tsv 2>/dev/null || echo "")
if [ -n "$EXISTING_KVS" ]; then
    echo "Found existing Key Vaults:"
    echo "$EXISTING_KVS"
    for KV in $EXISTING_KVS; do
        echo "Cleaning secrets from $KV..."
        SECRETS=$(az keyvault secret list --vault-name "$KV" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [ -n "$SECRETS" ]; then
            for SECRET in $SECRETS; do
                echo "  Deleting secret: $SECRET"
                az keyvault secret delete --vault-name "$KV" --name "$SECRET" 2>/dev/null || true
            done
            # Wait for deletion to complete before purging
            echo "  Waiting for deletions to complete..."
            sleep 2
            # Now purge the deleted secrets immediately
            for SECRET in $SECRETS; do
                echo "  Purging secret: $SECRET"
                az keyvault secret purge --vault-name "$KV" --name "$SECRET" 2>/dev/null || true
            done
            echo -e "${GREEN}✓ Cleaned all secrets from $KV${NC}"
        else
            echo "  No secrets found in $KV"
        fi
    done
fi

# Check for soft-deleted Key Vaults
echo -e "\n${YELLOW}Checking for soft-deleted Key Vaults...${NC}"
DELETED_KVS=$(az keyvault list-deleted --query "[?contains(name, 'dev-ocr-kv')]" -o json 2>/dev/null || echo "[]")
VAULT_NAMES=""

if [ "$DELETED_KVS" != "[]" ] && [ -n "$DELETED_KVS" ]; then
    VAULT_NAMES=$(echo "$DELETED_KVS" | jq -r '.[].name' 2>/dev/null || echo "")
    if [ -n "$VAULT_NAMES" ]; then
        echo "Found soft-deleted Key Vaults:"
        echo "$VAULT_NAMES"
    fi
fi

if [ -n "$VAULT_NAMES" ]; then
    echo "$VAULT_NAMES" | while read -r KV; do
        if [ -n "$KV" ]; then
            echo "Purging $KV..."
            # Try to purge with retry on failure
            PURGE_RETRY=0
            while [ $PURGE_RETRY -lt 2 ]; do
                if az keyvault purge --name "$KV" --no-wait 2>/dev/null; then
                    echo -e "${GREEN}✓ Purge initiated for $KV${NC}"
                    break
                else
                    PURGE_RETRY=$((PURGE_RETRY + 1))
                    if [ $PURGE_RETRY -lt 2 ]; then
                        echo "Purge failed, retrying in 3 seconds..."
                        sleep 3
                    else
                        echo -e "${YELLOW}⚠ Could not purge $KV (may already be purging)${NC}"
                    fi
                fi
            done
        fi
    done
    echo -e "${BLUE}Note: Key Vault purge operations running in background${NC}"
else
    echo "No soft-deleted Key Vaults found"
fi

# Check for orphaned resource groups (in case they failed to delete)
echo -e "\n${YELLOW}Checking for orphaned resource groups...${NC}"
RGS=$(az group list --query "[?contains(name, 'dev-ocr-rg')].name" -o tsv 2>/dev/null || echo "")
if [ -n "$RGS" ]; then
    echo "Found resource groups:"
    echo "$RGS"
    for RG in $RGS; do
        # Check for resource group budget
        echo "Checking for budget in $RG..."
        RG_BUDGETS=$(az consumption budget list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [ -n "$RG_BUDGETS" ]; then
            for BUDGET in $RG_BUDGETS; do
                echo "Deleting budget $BUDGET..."
                az consumption budget delete --budget-name "$BUDGET" --resource-group "$RG" 2>/dev/null || true
            done
        fi
        
        echo "Deleting resource group $RG..."
        az group delete --name "$RG" --yes --no-wait
        echo -e "${YELLOW}Resource group deletion initiated (will complete in background)${NC}"
    done
else
    echo "No orphaned resource groups found"
fi

# Check for orphaned role assignments (these can sometimes persist)
echo -e "\n${YELLOW}Checking for orphaned role assignments...${NC}"
# Look for role assignments to deleted service principals
ORPHANED_ASSIGNMENTS=$(az role assignment list --all --query "[?contains(principalName, 'dev-ocr') && principalType=='ServicePrincipal'].id" -o tsv 2>/dev/null || echo "")
if [ -n "$ORPHANED_ASSIGNMENTS" ]; then
    echo "Found orphaned role assignments"
    for ASSIGNMENT in $ORPHANED_ASSIGNMENTS; do
        echo "Removing role assignment: $ASSIGNMENT"
        az role assignment delete --ids "$ASSIGNMENT" 2>/dev/null || true
    done
    echo -e "${GREEN}✓ Cleaned up role assignments${NC}"
else
    echo "No orphaned role assignments found"
fi

echo -e "\n${GREEN}✅ Cleanup check complete!${NC}"
echo -e "${BLUE}If you still have issues, you may need to:${NC}"
echo "  1. Wait a few minutes for Azure to fully process deletions"
echo "  2. Check the Azure portal for any resources in 'Deleting' state"
echo "  3. Run 'terraform state list' to check for state inconsistencies"