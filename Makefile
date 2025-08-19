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
	@echo "  make init           - Initialize Terraform"
	@echo "  make plan           - Review what will be created"
	@echo "  make deploy         - Create everything in Azure (includes image check)"
	@echo "  make destroy        - Remove everything (fast, handles subscription resources)"
	@echo "  make destroy-slow   - Remove everything (tries clean Flux removal first)"
	@echo "  make destroy-nuclear - ☢️  Delete entire resource group (bypasses Terraform)"
	@echo "  make cleanup-orphans - Clean up any orphaned Azure resources"
	@echo "  make cleanup-keyvault - Clean up soft-deleted Key Vaults"
	@echo ""
	@echo "$(GREEN)Application:$(NC)"
	@echo "  make check-images   - Check if Docker images exist in ACR"
	@echo "  make build-images   - Build and push missing Docker images"
	@echo "  make force-images   - Force rebuild all Docker images"
	@echo "  make webapp         - 🌐 Launch OCR testing web app"
	@echo ""
	@echo "$(GREEN)Operations:$(NC)"
	@echo "  make connect        - Connect to AKS cluster"
	@echo "  make flux-status    - Check Flux GitOps sync status"
	@echo "  make pod-status     - Check application pod status"
	@echo "  make cost           - Check current costs"
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
	@echo "$(BLUE)Checking for orphaned resources from previous deployments...$(NC)"
	@./scripts/cleanup-orphans.sh || true
	@echo "$(BLUE)Creating Azure infrastructure and building Docker images...$(NC)"
	@cd $(TF_DIR) && terraform apply tfplan
	@echo "$(GREEN)✓ Infrastructure deployed and images built!$(NC)"
	@echo ""
	@echo "$(BLUE)Running post-deploy verification...$(NC)"
	@./scripts/post-deploy.sh 2>&1 | tee /tmp/post-deploy-output.txt || true
	@echo ""
	@if grep -q "Your OCR API is ready for testing" /tmp/post-deploy-output.txt 2>/dev/null; then \
		echo "$(GREEN)========================================$(NC)"; \
		echo "$(GREEN)✅ Deployment complete and API ready! ✅$(NC)"; \
		echo "$(GREEN)========================================$(NC)"; \
		echo ""; \
		echo "$(YELLOW)🚀 Test your deployment now:$(NC)"; \
		echo ""; \
		echo "    $(GREEN)make webapp$(NC)"; \
		echo ""; \
		echo "This launches a web interface for testing OCR!"; \
	else \
		echo "$(GREEN)✅ Deployment complete!$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Next steps:$(NC)"; \
		echo "  make webapp        - Launch OCR testing interface"; \
		echo "  make pod-status    - Check application pods"; \
		echo "  make connect       - Connect kubectl to cluster"; \
	fi
	@echo ""
	@echo "$(RED)Remember: make destroy when done (costs ~$$0.70/hour)$(NC)"

destroy:
	@echo "$(RED)This will DELETE everything!$(NC)"
	@read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ]
	@echo "$(BLUE)Optimizing destroy process...$(NC)"
	@echo "  Keeping subscription-level resources in state for proper cleanup..."
	@echo "  (Resource group deletion will cascade-delete everything inside)"
	@cd $(TF_DIR) && \
		for resource in $$(terraform state list 2>/dev/null | grep -v "^azurerm_resource_group\." | grep -v "^azurerm_key_vault\." | grep -v "^azurerm_role_assignment\..*_keyvault_" | grep -v "^azurerm_consumption_budget_subscription\." | grep -v "^azurerm_consumption_budget_resource_group\." | grep -v "^data\." || echo ""); do \
			echo "  Removing $$resource from state..." && \
			terraform state rm "$$resource" 2>/dev/null || true; \
		done
	@echo "$(BLUE)Destroying resource group and subscription budget...$(NC)"
	@cd $(TF_DIR) && terraform destroy -auto-approve -parallelism=30
	@echo "$(BLUE)Waiting for Azure to process deletions...$(NC)"
	@sleep 10
	@echo "$(BLUE)Running cleanup for soft-deleted resources...$(NC)"
	@./scripts/cleanup-orphans.sh || true
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

check-images:
	@./scripts/manage-images.sh check

build-images:
	@echo "$(BLUE)Building and pushing Docker images to ACR...$(NC)"
	@./scripts/manage-images.sh build

force-images:
	@echo "$(BLUE)Force rebuilding all Docker images...$(NC)"
	@./scripts/manage-images.sh force-build

pod-status:
	@echo "$(BLUE)Checking application pod status...$(NC)"
	@echo ""
	@echo "$(YELLOW)OCR API Pods:$(NC)"
	@kubectl get pods -n ocr -l app=ocr-api 2>/dev/null || echo "No API pods found"
	@echo ""
	@echo "$(YELLOW)OCR Worker Pods:$(NC)"
	@kubectl get pods -n ocr -l app=ocr-worker 2>/dev/null || echo "No worker pods found"
	@echo ""
	@echo "$(YELLOW)All Pods in OCR namespace:$(NC)"
	@kubectl get pods -n ocr 2>/dev/null || echo "OCR namespace not found"

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

destroy-slow:
	@echo "$(YELLOW)Attempting careful Flux cleanup before destroy...$(NC)"
	@read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ]
	@# Try to cleanly remove Flux from Azure first
	@cd $(TF_DIR) && \
		CLUSTER_NAME=$$(terraform output -raw aks_cluster_name 2>/dev/null || echo "") && \
		RG=$$(terraform output -raw resource_group_name 2>/dev/null || echo "") && \
		if [ -n "$$CLUSTER_NAME" ] && [ -n "$$RG" ]; then \
			echo "Removing Flux configuration from Azure..." && \
			timeout 60s az k8s-configuration flux delete \
				--name flux-system \
				--cluster-name "$$CLUSTER_NAME" \
				--resource-group "$$RG" \
				--cluster-type managedClusters \
				--yes --force 2>/dev/null || true && \
			echo "Removing Flux extension..." && \
			timeout 60s az k8s-extension delete \
				--name flux \
				--cluster-name "$$CLUSTER_NAME" \
				--resource-group "$$RG" \
				--cluster-type managedClusters \
				--yes --force 2>/dev/null || true; \
		fi
	@echo "$(BLUE)Running terraform destroy...$(NC)"
	@cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "$(GREEN)✓ Everything removed$(NC)"

destroy-nuclear:
	@echo "$(RED)☢️  NUCLEAR OPTION - Deleting entire resource group and budgets!$(NC)"
	@read -p "Type 'NUCLEAR' to confirm: " confirm && [ "$$confirm" = "NUCLEAR" ]
	@cd $(TF_DIR) && \
		RG=$$(terraform output -raw resource_group_name 2>/dev/null || echo "") && \
		SUBSCRIPTION=$$(az account show --query id -o tsv) && \
		if [ -n "$$RG" ]; then \
			echo "$(YELLOW)Deleting budgets...$(NC)" && \
			az consumption budget delete --budget-name "dev-ocr-budget-monthly" 2>/dev/null || true && \
			az consumption budget delete --budget-name "dev-ocr-budget-rg" --resource-group "$$RG" 2>/dev/null || true && \
			echo "$(YELLOW)Deleting resource group $$RG...$(NC)" && \
			az group delete --name $$RG --yes --no-wait && \
			echo "$(YELLOW)Clearing Terraform state...$(NC)" && \
			terraform state pull | jq 'del(.resources) | .serial += 1' | terraform state push - && \
			echo "$(GREEN)✓ Resource group deletion initiated (will complete in background)$(NC)"; \
		else \
			echo "$(RED)Could not find resource group$(NC)"; \
		fi

cleanup-orphans:
	@echo "$(BLUE)Checking for orphaned Azure resources...$(NC)"
	@./scripts/cleanup-orphans.sh

cleanup-keyvault:
	@echo "$(BLUE)Checking for soft-deleted Key Vaults...$(NC)"
	@./scripts/cleanup-keyvault.sh

webapp:
	@if [ ! -f webapp/api-config.json ]; then \
		echo "$(RED)ERROR: webapp/api-config.json not found$(NC)"; \
		echo "Run 'make deploy' first to set up the API"; \
		exit 1; \
	fi
	@echo "$(BLUE)Starting OCR testing web app with proxy...$(NC)"
	@echo ""
	@sleep 1 && (open http://localhost:8080 2>/dev/null || xdg-open http://localhost:8080 2>/dev/null || echo "") & \
		python3 webapp/proxy_server.py

clean:
	@rm -rf $(TF_DIR)/.terraform $(TF_DIR)/tfplan $(TF_DIR)/.terraform.lock.hcl
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: help init plan deploy destroy destroy-slow destroy-nuclear cleanup-orphans cleanup-keyvault connect flux-status check-images build-images force-images pod-status cost outputs webapp clean