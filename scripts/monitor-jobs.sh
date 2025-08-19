#!/bin/bash

# OCR Job Monitoring Script - Monitors job completion and system scaling
# Usage: ./monitor-jobs.sh [job_ids_file]
# Example: ./monitor-jobs.sh /tmp/ocr_job_ids_1234.txt

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default values
JOB_FILE=${1:-"/tmp/ocr_job_ids_$$.txt"}
MONITORING_INTERVAL=${2:-5}
NAMESPACE="ocr"

# Validate inputs
if [ ! -f "$JOB_FILE" ]; then
    echo -e "${RED}Error: Job file '$JOB_FILE' not found${NC}"
    echo ""
    echo "Available job files:"
    ls -la /tmp/ocr_job_ids_*.txt 2>/dev/null || echo "  No job files found"
    echo ""
    echo "Usage: $0 <job_ids_file> [monitoring_interval]"
    exit 1
fi

# Get API URL from webapp config or environment
if [ -f "../webapp/api-config.json" ]; then
    API_URL=$(jq -r '.apiUrl' ../webapp/api-config.json)
elif [ -f "webapp/api-config.json" ]; then
    API_URL=$(jq -r '.apiUrl' webapp/api-config.json)
else
    # Try to get from gateway
    GATEWAY_ADDRESS=$(kubectl get gateway ocr-gateway -n ocr -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -n "$GATEWAY_ADDRESS" ]; then
        API_URL="http://${GATEWAY_ADDRESS}"
    else
        echo -e "${RED}Error: Could not determine API URL${NC}"
        echo "Please ensure the OCR API is deployed and accessible"
        exit 1
    fi
fi

# Read job IDs into array (macOS compatible)
JOB_IDS=()
while IFS= read -r line; do
    JOB_IDS+=("$line")
done < "$JOB_FILE"
declare -a JOB_STATUSES=()

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}              OCR Job Monitoring Dashboard                       ${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  • Jobs to monitor: ${BOLD}${#JOB_IDS[@]}${NC}"
echo -e "  • Job file: ${BOLD}$JOB_FILE${NC}"
echo -e "  • API URL: ${BOLD}$API_URL${NC}"
echo -e "  • Update interval: ${BOLD}${MONITORING_INTERVAL}s${NC}"
echo ""

# Function to get queue depth from Service Bus
get_queue_depth() {
    local namespace=$(kubectl get secret cluster-config -n ocr -o jsonpath='{.data.SERVICE_BUS_NAMESPACE}' | base64 -d)
    local rg=$(kubectl get secret cluster-config -n ocr -o jsonpath='{.data.RESOURCE_GROUP}' | base64 -d)
    
    if [ -n "$namespace" ] && [ -n "$rg" ]; then
        az servicebus queue show --name ocr-jobs --namespace-name "$namespace" --resource-group "$rg" \
            --query "countDetails.activeMessageCount" -o tsv 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# Function to print system snapshot
print_system_state() {
    local label=$1
    echo -e "\n${BOLD}${CYAN}=== $label ===${NC}"
    
    # Nodes
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready || echo "0")
    local user_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep user | wc -l | tr -d ' ')
    echo -e "${MAGENTA}🖥️  Nodes:${NC} Total: $node_count | User pool: $user_nodes"
    
    # Pods
    local api_pods=$(kubectl get pods -n $NAMESPACE -l app=ocr-api --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local worker_pods=$(kubectl get pods -n $NAMESPACE -l app=ocr-worker --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local running_workers=$(kubectl get pods -n $NAMESPACE -l app=ocr-worker --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local pending_workers=$(kubectl get pods -n $NAMESPACE -l app=ocr-worker --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    echo -ne "${GREEN}🔷 Pods:${NC} API: $api_pods | Workers: $worker_pods"
    if [ $pending_workers -gt 0 ]; then
        echo " (${running_workers} running, ${YELLOW}$pending_workers pending${NC})"
    else
        echo " (${running_workers} running)"
    fi
    
    # Queue
    local queue_depth=$(get_queue_depth)
    echo -e "${YELLOW}📬 Queue:${NC} $queue_depth messages"
    
    # HPA/KEDA status with better formatting
    local api_metrics=$(kubectl get hpa ocr-api -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $3}')
    local api_replicas=$(kubectl get hpa ocr-api -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $6}')
    local worker_replicas=$(kubectl get hpa keda-hpa-ocr-worker-scaler -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $6}')
    
    echo -e "${BLUE}📊 Scaling:${NC} API: $api_replicas pods ($api_metrics) | Workers: $worker_replicas pods"
}

# Function to verify a completed job by downloading result
verify_job_result() {
    local job_id=$1
    local result=$(curl -s "${API_URL}/ocr/${job_id}/result" 2>/dev/null)
    
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        local length=${#result}
        if [ $length -gt 100 ]; then
            echo "✓ (${length} chars)"
            return 0
        else
            echo "⚠ (only ${length} chars)"
            return 1
        fi
    else
        echo "✗ (no result)"
        return 1
    fi
}

# Function to check job statuses with better performance
check_job_completion() {
    local completed=0
    local pending=0
    local processing=0
    local failed=0
    local total=${#JOB_IDS[@]}
    
    if [ $total -eq 0 ]; then
        echo -e "${YELLOW}No jobs to check${NC}"
        return 1
    fi
    
    echo -ne "${CYAN}Checking job statuses...${NC}"
    
    # Check jobs in parallel for better performance
    for i in "${!JOB_IDS[@]}"; do
        job_id="${JOB_IDS[$i]}"
        if [ -n "$job_id" ]; then
            # Skip if already completed or failed
            if [ "${JOB_STATUSES[$i]}" != "completed" ] && [ "${JOB_STATUSES[$i]}" != "failed" ]; then
                status=$(curl -s "${API_URL}/ocr/${job_id}" | jq -r '.status' 2>/dev/null || echo "error")
                JOB_STATUSES[$i]=$status
            else
                status="${JOB_STATUSES[$i]}"
            fi
            
            case $status in
                completed) ((completed++)) ;;
                processing) ((processing++)) ;;
                pending) ((pending++)) ;;
                *) ((failed++)) ;;
            esac
        fi
    done
    
    echo -ne "\r\033[K"  # Clear the checking message
    
    local pct=0
    if [ $total -gt 0 ]; then
        pct=$((completed * 100 / total))
    fi
    
    # Progress bar
    local bar_length=30
    local filled=$((pct * bar_length / 100))
    local empty=$((bar_length - filled))
    
    echo -ne "${CYAN}📋 Progress:${NC} ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    echo -e "] ${BOLD}$pct%${NC}"
    
    echo -e "${CYAN}📈 Status:${NC} Total: $total | ✅ Complete: ${GREEN}$completed${NC} | 🔄 Processing: ${CYAN}$processing${NC} | ⏳ Pending: ${YELLOW}$pending${NC}"
    
    if [ $failed -gt 0 ]; then
        echo -e "  ❌ Failed: ${RED}$failed${NC}"
    fi
    
    # Return 0 if all complete, 1 otherwise
    if [ $completed -eq $total ]; then
        return 0
    else
        return 1
    fi
}

# Main monitoring loop
START_TIME=$(date +%s)

# Initial state
print_system_state "Initial State"

echo -e "\n${BOLD}${BLUE}Starting continuous monitoring...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"

# Set up clean exit
trap "echo -e '\n\n${YELLOW}Monitoring stopped by user${NC}'; exit 0" INT

ITERATION=0
MAX_NODES=0
MAX_WORKERS=0

while true; do
    sleep $MONITORING_INTERVAL
    ((ITERATION++))
    
    # Calculate elapsed time
    ELAPSED=$(($(date +%s) - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))
    
    echo -e "\n${BOLD}${CYAN}═══ Update #$ITERATION ═══ ${NC}${YELLOW}[${MINUTES}m ${SECONDS}s elapsed]${NC}"
    
    # Check job completion
    check_job_completion
    
    # Calculate processing metrics
    completed_count=0
    for status in "${JOB_STATUSES[@]}"; do
        if [ "$status" == "completed" ]; then
            ((completed_count++))
        fi
    done
    
    if [ $ELAPSED -gt 0 ] && [ $completed_count -gt 0 ]; then
        rate=$(echo "scale=2; $completed_count * 60 / $ELAPSED" | bc)
        echo -e "${MAGENTA}⚡ Processing rate:${NC} $rate jobs/min"
        
        # ETA calculation
        remaining=$((${#JOB_IDS[@]} - completed_count))
        if [ $remaining -gt 0 ] && [ $completed_count -gt 0 ]; then
            eta_seconds=$(echo "scale=0; $remaining * $ELAPSED / $completed_count" | bc)
            eta_minutes=$((eta_seconds / 60))
            eta_secs=$((eta_seconds % 60))
            echo -e "${MAGENTA}⏱️  ETA:${NC} ${eta_minutes}m ${eta_secs}s"
        fi
    fi
    
    # Show system state
    print_system_state "Current State"
    
    # Track max scaling
    current_workers=$(kubectl get pods -n $NAMESPACE -l app=ocr-worker --no-headers 2>/dev/null | wc -l | tr -d ' ')
    current_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready || echo "0")
    
    if [ $current_workers -gt $MAX_WORKERS ]; then
        MAX_WORKERS=$current_workers
        echo -e "${GREEN}📈 New max workers: $MAX_WORKERS${NC}"
    fi
    
    if [ $current_nodes -gt $MAX_NODES ]; then
        MAX_NODES=$current_nodes
        echo -e "${GREEN}📈 New max nodes: $MAX_NODES${NC}"
    fi
    
    # Check if all jobs are complete
    if check_job_completion >/dev/null 2>&1; then
        echo -e "\n${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}                    🎉 ALL JOBS COMPLETED! 🎉                    ${NC}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Total time: ${MINUTES}m ${SECONDS}s${NC}"
        echo -e "${GREEN}Max scaling: $MAX_WORKERS workers, $MAX_NODES nodes${NC}"
        
        # Verify some results
        echo -e "\n${CYAN}Verifying results (sampling up to 5 jobs)...${NC}"
        sample_size=5
        if [ ${#JOB_IDS[@]} -lt $sample_size ]; then
            sample_size=${#JOB_IDS[@]}
        fi
        
        for ((j=0; j<sample_size; j++)); do
            job_id="${JOB_IDS[$j]}"
            echo -ne "  Job ${job_id:0:12}... "
            verify_job_result "$job_id"
        done
        
        # Final system state
        print_system_state "Final State"
        
        echo -e "\n${YELLOW}Monitoring complete!${NC}"
        echo -e "${CYAN}Job results can be retrieved using:${NC}"
        echo -e "  ${BOLD}curl ${API_URL}/ocr/<job_id>/result${NC}"
        exit 0
    fi
    
    # Show recent scaling events (limited to avoid spam)
    if [ $((ITERATION % 3)) -eq 0 ]; then
        echo -e "\n${MAGENTA}📌 Recent events:${NC}"
        kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' 2>/dev/null | \
            grep -E "(Scaled|Created|Started|Pulling)" | tail -3 | \
            awk '{printf "  • %s %s\n", $1, $NF}'
    fi
done