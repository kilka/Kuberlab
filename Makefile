# Simplified OCR AKS Infrastructure Makefile
# Uses Terraform outputs instead of hardcoded variables

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Only configuration needed
TF_DIR := infra

.DEFAULT_GOAL := help

help:
	@echo "$(BLUE)OCR AKS Infrastructure$(NC)"
	@echo "======================="
	@echo ""
	@echo "$(GREEN)Commands:$(NC)"
	@echo "  make init        - Initialize Terraform"
	@echo "  make plan        - Review what will be created"
	@echo "  make deploy      - Create everything in Azure"
	@echo "  make destroy     - Remove everything from Azure (zero traces!)"
	@echo "  make connect     - Connect to AKS cluster"
	@echo "  make flux-status - Check Flux GitOps sync status"
	@echo "  make cost        - Check current costs"
	@echo ""
	@echo "$(YELLOW)⚠ Costs: ~$$0.70/hour when deployed$(NC)"

init:
	@echo "$(BLUE)Initializing...$(NC)"
	@cd $(TF_DIR) && terraform init -upgrade
	@echo "$(GREEN)✓ Ready$(NC)"

plan: init
	@echo "$(BLUE)Planning...$(NC)"
	@if [ ! -f $(TF_DIR)/terraform.tfvars ]; then \
		echo "$(YELLOW)Creating terraform.tfvars from template...$(NC)"; \
		cp $(TF_DIR)/terraform.tfvars.example $(TF_DIR)/terraform.tfvars; \
		echo "$(YELLOW)Enter your email for budget alerts:$(NC)"; \
		read -p "Email: " email; \
		sed -i.bak "s/your-email@example.com/$$email/g" $(TF_DIR)/terraform.tfvars; \
		rm $(TF_DIR)/terraform.tfvars.bak; \
	fi
	@if grep -q "your-email@example.com" $(TF_DIR)/terraform.tfvars 2>/dev/null; then \
		echo "$(RED)ERROR: Update budget_alert_email in $(TF_DIR)/terraform.tfvars$(NC)"; \
		exit 1; \
	fi
	@cd $(TF_DIR) && terraform plan -out=tfplan
	@echo "$(GREEN)✓ Plan ready$(NC)"

deploy: plan
	@echo "$(YELLOW)This will create ~40 Azure resources (~$$0.70/hour)$(NC)"
	@read -p "Deploy? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	@cd $(TF_DIR) && terraform apply tfplan
	@echo "$(GREEN)✓ Deployed!$(NC)"
	@echo ""
	@echo "$(YELLOW)Connect with: make connect$(NC)"
	@echo "$(RED)Remember: make destroy when done!$(NC)"

destroy:
	@echo "$(RED)This will DELETE everything!$(NC)"
	@read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ]
	@cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "$(GREEN)✓ Everything removed$(NC)"

connect:
	@echo "$(BLUE)Connecting to AKS...$(NC)"
	@cd $(TF_DIR) && \
		RG=$$(terraform output -raw resource_group_name 2>/dev/null) && \
		AKS=$$(terraform output -raw aks_cluster_name 2>/dev/null) && \
		az aks get-credentials --resource-group $$RG --name $$AKS --overwrite-existing
	@echo "$(GREEN)✓ Connected$(NC)"
	@kubectl get nodes

flux-status:
	@echo "$(BLUE)Checking Flux GitOps sync...$(NC)"
	@kubectl get kustomizations -n flux-system || echo "Flux not yet installed"
	@kubectl get helmreleases -A 2>/dev/null || true
	@kubectl get pods -n flux-system 2>/dev/null || true

cost:
	@echo "$(BLUE)Checking costs...$(NC)"
	@cd $(TF_DIR) && \
		RG=$$(terraform output -raw resource_group_name 2>/dev/null) && \
		echo "Resource Group: $$RG" && \
		az cost management query --type Usage \
			--scope "subscriptions/$$(az account show --query id -o tsv)/resourceGroups/$$RG" \
			--timeframe MonthToDate \
			--dataset-aggregation '{\"totalCost\":{\"name\":\"PreTaxCost\",\"function\":\"Sum\"}}' \
			--query 'rows[0][0]' -o tsv 2>/dev/null | \
			xargs printf "Month-to-date cost: $$%.2f\n" || echo "No cost data yet"

outputs:
	@cd $(TF_DIR) && terraform output

clean:
	@rm -rf $(TF_DIR)/.terraform $(TF_DIR)/tfplan $(TF_DIR)/.terraform.lock.hcl
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: help init plan deploy destroy connect flux-status cost outputs clean