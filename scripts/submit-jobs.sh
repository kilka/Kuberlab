#!/bin/bash

# OCR Job Submission Script - Submits jobs in parallel
# Usage: ./submit-jobs.sh [number_of_jobs] [test_image]
# Example: ./submit-jobs.sh 100 test_image.png

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
PARALLEL_JOBS=50  # Number of parallel submissions
OUTPUT_FILE="/tmp/ocr_job_ids_$$.txt"

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

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}              OCR Parallel Job Submission Script                 ${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  • Number of jobs: ${BOLD}$NUM_JOBS${NC}"
echo -e "  • Test image: ${BOLD}$TEST_IMAGE${NC}"
echo -e "  • API URL: ${BOLD}$API_URL${NC}"
echo -e "  • Parallel submissions: ${BOLD}$PARALLEL_JOBS${NC}"
echo -e "  • Output file: ${BOLD}$OUTPUT_FILE${NC}"
echo ""

# Clear output file
> "$OUTPUT_FILE"

# Function to create unique test image with timestamp
create_unique_image() {
    local job_num=$1
    local temp_image="/tmp/test_image_${job_num}_$$_${RANDOM}.png"
    
    # Try to add unique text overlay to make each image different
    if command -v convert &> /dev/null; then
        convert "${TEST_IMAGE}" \
            -pointsize 30 \
            -fill red \
            -annotate +50+50 "Job #${job_num} - $(date +%s%N) - ${RANDOM}" \
            "$temp_image" 2>/dev/null || cp "${TEST_IMAGE}" "$temp_image"
    else
        # If ImageMagick not available, at least try to make unique by adding random data
        cp "${TEST_IMAGE}" "$temp_image"
        echo "Job${job_num}_${RANDOM}_$(date +%s%N)" >> "$temp_image"
    fi
    
    echo "$temp_image"
}

# Function to submit a single job
submit_job() {
    local job_num=$1
    
    # Create unique image for this job
    local unique_image=$(create_unique_image $job_num)
    
    # Use curl with more details and timeout
    local response=$(curl -s -X POST "${API_URL}/ocr" \
        -F "file=@${unique_image}" \
        -H "Accept: application/json" \
        --max-time 30 \
        -w "\nHTTP_CODE:%{http_code}" 2>&1)
    
    local exit_code=$?
    
    # Clean up temp image
    rm -f "$unique_image" 2>/dev/null
    
    # Extract HTTP code and response body
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    local body=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    if [ $exit_code -eq 0 ] && ([ "$http_code" = "200" ] || [ "$http_code" = "202" ]); then
        local job_id=$(echo "$body" | jq -r '.job_id' 2>/dev/null)
        if [ -n "$job_id" ] && [ "$job_id" != "null" ]; then
            echo "$job_id" >> "$OUTPUT_FILE"
            echo -e "${GREEN}✓${NC} Job $job_num: ${job_id:0:12}..."
            return 0
        else
            echo -e "${RED}✗${NC} Job $job_num: Invalid response"
            return 1
        fi
    else
        # Show error details
        if [ $exit_code -eq 28 ]; then
            echo -e "${RED}✗${NC} Job $job_num: Timeout (30s)"
        elif [ -n "$http_code" ] && [ "$http_code" != "200" ]; then
            echo -e "${RED}✗${NC} Job $job_num: HTTP $http_code"
            if [ -n "$body" ]; then
                echo "    Error: $(echo "$body" | jq -r '.detail // .message // .' 2>/dev/null | head -1)"
            fi
        else
            echo -e "${RED}✗${NC} Job $job_num: Connection failed (code: $exit_code)"
        fi
        return 1
    fi
}

# Record start time
START_TIME=$(date +%s)

echo -e "${BOLD}${BLUE}Starting parallel job submission...${NC}"
echo ""

# Submit jobs in parallel batches
SUBMITTED=0
FAILED=0

# Keep parallel jobs constant regardless of job count
# This allows for maximum submission speed

for ((i=1; i<=NUM_JOBS; i+=$PARALLEL_JOBS)); do
    # Calculate batch size (handle last batch)
    BATCH_END=$((i + PARALLEL_JOBS - 1))
    if [ $BATCH_END -gt $NUM_JOBS ]; then
        BATCH_END=$NUM_JOBS
    fi
    
    echo -e "${CYAN}Submitting batch: jobs $i-$BATCH_END${NC}"
    
    # Launch parallel jobs
    for ((j=i; j<=BATCH_END; j++)); do
        submit_job $j &
    done
    
    # Wait for batch to complete
    wait
    
    # Small pause between batches to avoid overwhelming the API
    if [ $BATCH_END -lt $NUM_JOBS ]; then
        sleep 0.5
    fi
    
    # Extra pause every 100 jobs to let the system catch up
    if [ $((i % 100)) -eq 0 ] && [ $i -lt $NUM_JOBS ]; then
        echo -e "${YELLOW}Pausing 3 seconds to let system stabilize...${NC}"
        sleep 3
    fi
done

# Count successful submissions
TOTAL_SUBMITTED=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Submission Complete!${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Results:${NC}"
echo -e "  • Jobs submitted: ${BOLD}$TOTAL_SUBMITTED/$NUM_JOBS${NC}"
echo -e "  • Time taken: ${BOLD}${DURATION}s${NC}"
echo -e "  • Submission rate: ${BOLD}$(echo "scale=2; $TOTAL_SUBMITTED / $DURATION" | bc) jobs/sec${NC}"
echo -e "  • Job IDs saved to: ${BOLD}$OUTPUT_FILE${NC}"
echo ""
echo -e "${CYAN}To monitor these jobs, run:${NC}"
echo -e "  ${BOLD}./monitor-jobs.sh $OUTPUT_FILE${NC}"
echo ""

# Show first few job IDs as confirmation
echo -e "${MAGENTA}Sample job IDs:${NC}"
head -5 "$OUTPUT_FILE" | while read job_id; do
    echo "  • ${job_id:0:16}..."
done

if [ $(wc -l < "$OUTPUT_FILE") -gt 5 ]; then
    echo "  • ... and $((TOTAL_SUBMITTED - 5)) more"
fi