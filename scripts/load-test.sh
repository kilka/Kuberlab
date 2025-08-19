#!/bin/bash

# OCR Load Testing Script with Real-time Monitoring
# Usage: ./load-test.sh [number_of_jobs] [test_image]
# Example: ./load-test.sh 100 test_image.png

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
NUM_JOBS=${1:-50}
TEST_IMAGE=${2:-"../test_image.png"}
MONITORING_INTERVAL=5
NAMESPACE="ocr"

# Validate inputs
if ! [[ "$NUM_JOBS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Number of jobs must be a positive integer${NC}"
    exit 1
fi

if [ ! -f "$TEST_IMAGE" ]; then
    echo -e "${RED}Error: Test image '$TEST_IMAGE' not found${NC}"
    exit 1
fi

# Get API URL from webapp config or environment
if [ -f "webapp/api-config.json" ]; then
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

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}           OCR Load Testing - Autoscaling Demo                   ${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  • Number of jobs: ${BOLD}$NUM_JOBS${NC}"
echo -e "  • Test image: ${BOLD}$TEST_IMAGE${NC}"
echo -e "  • API URL: ${BOLD}$API_URL${NC}"
echo -e "  • Monitoring interval: ${BOLD}${MONITORING_INTERVAL}s${NC}"
echo ""

# Array to store job IDs
declare -a JOB_IDS=()
declare -a JOB_STATUSES=()

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

# Function to create unique test image with timestamp
create_unique_image() {
    local job_num=$1
    local temp_image="/tmp/test_image_${job_num}_$$.png"
    
    # Add unique text overlay to make each image different
    convert "${TEST_IMAGE}" \
        -pointsize 30 \
        -fill red \
        -annotate +50+50 "Job #${job_num} - $(date +%s%N)" \
        "$temp_image" 2>/dev/null || cp "${TEST_IMAGE}" "$temp_image"
    
    echo "$temp_image"
}

# Function to submit a single job
submit_job() {
    local job_num=$1
    
    # Create unique image for this job
    local unique_image=$(create_unique_image $job_num)
    
    local response=$(curl -s -X POST "${API_URL}/ocr" \
        -F "file=@${unique_image}" \
        -H "Accept: application/json" 2>/dev/null)
    
    # Clean up temp image
    rm -f "$unique_image" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local job_id=$(echo "$response" | jq -r '.job_id' 2>/dev/null)
        if [ -n "$job_id" ] && [ "$job_id" != "null" ]; then
            echo -ne "\r${GREEN}✓${NC} Submitted job $job_num/$NUM_JOBS (ID: ${job_id:0:8}...)"
            JOB_IDS+=("$job_id")
            return 0
        fi
    fi
    
    echo -e "\n${RED}✗${NC} Failed to submit job $job_num"
    return 1
}

# Function to print system snapshot
print_system_state() {
    local label=$1
    echo -e "\n${BOLD}${CYAN}=== $label ===${NC}"
    
    # Nodes
    local node_count=$(kubectl get nodes --no-headers | grep -c Ready || echo "0")
    local user_nodes=$(kubectl get nodes --no-headers | grep user | wc -l | tr -d ' ')
    echo -e "${MAGENTA}Nodes:${NC} Total: $node_count | User pool: $user_nodes"
    
    # Pods
    local api_pods=$(kubectl get pods -n $NAMESPACE -l app=ocr-api --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local worker_pods=$(kubectl get pods -n $NAMESPACE -l app=ocr-worker --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local running_workers=$(kubectl get pods -n $NAMESPACE -l app=ocr-worker --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo -e "${GREEN}Pods:${NC} API: $api_pods | Workers: $worker_pods (${running_workers} running)"
    
    # Queue
    local queue_depth=$(get_queue_depth)
    echo -e "${YELLOW}Queue:${NC} $queue_depth messages"
    
    # HPA/KEDA status
    local api_hpa=$(kubectl get hpa ocr-api -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $3}')
    local worker_scale=$(kubectl get hpa keda-hpa-ocr-worker-scaler -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $6}')
    echo -e "${BLUE}Scaling:${NC} API HPA: $api_hpa | Worker replicas: $worker_scale"
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

# Function to check job statuses
check_job_completion() {
    local completed=0
    local pending=0
    local processing=0
    local failed=0
    local total=${#JOB_IDS[@]}
    
    if [ $total -eq 0 ]; then
        echo -e "${YELLOW}No jobs to check${NC}"
        return
    fi
    
    echo -ne "${CYAN}Checking job statuses...${NC}"
    
    for i in "${!JOB_IDS[@]}"; do
        job_id="${JOB_IDS[$i]}"
        if [ -n "$job_id" ]; then
            # Check cached status first to reduce API calls
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
    
    echo -e "${CYAN}Job Status:${NC} Total: $total | ✅ Completed: ${GREEN}$completed ($pct%)${NC} | 🔄 Processing: ${CYAN}$processing${NC} | ⏳ Pending: ${YELLOW}$pending${NC}"
    
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

# Main execution
echo -e "${BOLD}${GREEN}Starting load test...${NC}"
echo ""

# Record initial state
START_TIME=$(date +%s)
print_system_state "Initial State"

# Submit jobs
echo -e "\n${BOLD}${BLUE}=== Phase 1: Submitting Jobs ===${NC}"
BATCH_SIZE=10

for ((i=1; i<=NUM_JOBS; i++)); do
    submit_job $i
    
    # New line after each batch for readability
    if [ $((i % BATCH_SIZE)) -eq 0 ] || [ $i -eq $NUM_JOBS ]; then
        echo ""  # New line after batch
    fi
    
    # Brief pause between large batches to avoid overwhelming the API
    if [ $((i % 50)) -eq 0 ] && [ $i -lt $NUM_JOBS ]; then
        echo -e "\n${YELLOW}Pausing briefly before next batch...${NC}"
        sleep 2
    fi
done

echo -e "\n${GREEN}✓ All jobs submitted!${NC}"
echo -e "${YELLOW}Total submitted: ${#JOB_IDS[@]}/$NUM_JOBS${NC}"

# Monitoring phase
echo -e "\n${BOLD}${BLUE}=== Phase 2: Monitoring System Scaling ===${NC}"
echo -e "${YELLOW}Monitoring every ${MONITORING_INTERVAL}s - Press Ctrl+C to stop${NC}"

# Set up clean exit
trap "echo -e '\n\n${YELLOW}Monitoring stopped by user${NC}'; exit 0" INT

ITERATION=0
while true; do
    sleep $MONITORING_INTERVAL
    ((ITERATION++))
    
    # Calculate elapsed time
    ELAPSED=$(($(date +%s) - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))
    
    echo -e "\n${BOLD}${CYAN}=== Update #$ITERATION (${MINUTES}m ${SECONDS}s elapsed) ===${NC}"
    
    # Show system state
    print_system_state "Current State"
    
    # Check job completion
    check_job_completion
    
    # Calculate and show processing rate
    completed_count=0
    for status in "${JOB_STATUSES[@]}"; do
        if [ "$status" == "completed" ]; then
            ((completed_count++))
        fi
    done
    
    if [ $ELAPSED -gt 0 ] && [ $completed_count -gt 0 ]; then
        rate=$(echo "scale=2; $completed_count * 60 / $ELAPSED" | bc)
        echo -e "${MAGENTA}Processing rate:${NC} $rate jobs/min"
        
        # ETA calculation
        remaining=$((${#JOB_IDS[@]} - completed_count))
        if [ $remaining -gt 0 ] && [ $completed_count -gt 0 ]; then
            eta_seconds=$(echo "scale=0; $remaining * $ELAPSED / $completed_count" | bc)
            eta_minutes=$((eta_seconds / 60))
            eta_secs=$((eta_seconds % 60))
            echo -e "${MAGENTA}ETA:${NC} ${eta_minutes}m ${eta_secs}s"
        fi
    fi
    
    # Check if all jobs are complete
    if check_job_completion >/dev/null 2>&1; then
        echo -e "\n${GREEN}${BOLD}🎉 ALL JOBS COMPLETED! 🎉${NC}"
        echo -e "${GREEN}Total time: ${MINUTES}m ${SECONDS}s${NC}"
        
        # Verify some results by downloading them
        echo -e "\n${CYAN}Verifying results (sampling 5 jobs)...${NC}"
        verified=0
        sample_size=5
        if [ ${#JOB_IDS[@]} -lt $sample_size ]; then
            sample_size=${#JOB_IDS[@]}
        fi
        
        for ((j=0; j<sample_size; j++)); do
            job_id="${JOB_IDS[$j]}"
            echo -ne "  Job ${job_id:0:8}... "
            verify_job_result "$job_id"
        done
        
        # Final system state
        print_system_state "Final State"
        
        echo -e "\n${YELLOW}Load test complete!${NC}"
        exit 0
    fi
    
    # Show a few recent events
    echo -e "${MAGENTA}Recent events:${NC}"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -3 | \
        awk '{if(NR>1) printf "  • %s: %s\n", $1, $NF}'
done