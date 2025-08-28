#!/bin/bash

# OCR Job Submission Script - Direct Upload Version
# Usage: ./submit-jobs-direct.sh [number_of_jobs] [test_image]
# Example: ./submit-jobs-direct.sh 500 test_image.png

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
PARALLEL_JOBS=50   # Reduced for better reliability (was 100, causing connection issues)
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
echo -e "${BOLD}${CYAN}         OCR Direct Upload Job Submission Script                 ${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  • Number of jobs: ${BOLD}$NUM_JOBS${NC}"
echo -e "  • Test image: ${BOLD}$TEST_IMAGE${NC}"
echo -e "  • API URL: ${BOLD}$API_URL${NC}"
echo -e "  • Parallel submissions: ${BOLD}$PARALLEL_JOBS${NC}"
echo -e "  • Output file: ${BOLD}$OUTPUT_FILE${NC}"
echo -e "  • Upload method: ${BOLD}Direct to Blob Storage${NC}"
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

# Function to submit a single job using direct upload
submit_job_direct() {
    local job_num=$1
    local unique_image=$(create_unique_image $job_num)
    local filename=$(basename "$unique_image")
    
    # Step 1: Get upload URL
    local upload_response=$(curl -s -X POST "${API_URL}/generate-upload-url?filename=${filename}" \
        --max-time 10 \
        -w "\nHTTP_CODE:%{http_code}" 2>&1)
    
    local upload_exit_code=$?
    local upload_http_code=$(echo "$upload_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local upload_body=$(echo "$upload_response" | sed '/HTTP_CODE:/d')
    
    if [ $upload_exit_code -ne 0 ] || [ "$upload_http_code" != "200" ]; then
        rm -f "$unique_image" 2>/dev/null
        echo -e "${RED}✗${NC} Job $job_num: Failed to get upload URL (HTTP $upload_http_code)"
        return 1
    fi
    
    # Extract job_id and upload_url from response
    local job_id=$(echo "$upload_body" | jq -r '.job_id' 2>/dev/null)
    local upload_url=$(echo "$upload_body" | jq -r '.upload_url' 2>/dev/null)
    
    if [ -z "$job_id" ] || [ "$job_id" = "null" ] || [ -z "$upload_url" ] || [ "$upload_url" = "null" ]; then
        rm -f "$unique_image" 2>/dev/null
        echo -e "${RED}✗${NC} Job $job_num: Invalid upload URL response"
        return 1
    fi
    
    # Step 2: Upload directly to blob storage
    local direct_upload_response=$(curl -s -X PUT "$upload_url" \
        -H "x-ms-blob-type: BlockBlob" \
        -T "$unique_image" \
        --max-time 30 \
        -w "\nHTTP_CODE:%{http_code}" 2>&1)
    
    local direct_exit_code=$?
    local direct_http_code=$(echo "$direct_upload_response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [ $direct_exit_code -ne 0 ] || [ "$direct_http_code" != "201" ]; then
        rm -f "$unique_image" 2>/dev/null
        echo -e "${RED}✗${NC} Job $job_num: Direct upload failed (HTTP $direct_http_code)"
        return 1
    fi
    
    # Step 3: Confirm upload and queue job
    local confirm_response=$(curl -s -X POST "${API_URL}/ocr/confirm-upload?job_id=${job_id}&filename=${filename}" \
        --max-time 15 \
        --retry 2 \
        --retry-delay 1 \
        -w "\nHTTP_CODE:%{http_code}" 2>&1)
    
    local confirm_exit_code=$?
    local confirm_http_code=$(echo "$confirm_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local confirm_body=$(echo "$confirm_response" | sed '/HTTP_CODE:/d')
    
    # Clean up temp image
    rm -f "$unique_image" 2>/dev/null
    
    if [ $confirm_exit_code -eq 0 ] && ([ "$confirm_http_code" = "200" ] || [ "$confirm_http_code" = "202" ]); then
        echo "$job_id" >> "$OUTPUT_FILE"
        echo -e "${GREEN}✓${NC} Job $job_num: ${job_id:0:12}... (direct upload)"
        return 0
    else
        echo -e "${RED}✗${NC} Job $job_num: Confirm failed (HTTP $confirm_http_code)"
        if [ -n "$confirm_body" ]; then
            echo "    Error: $(echo "$confirm_body" | jq -r '.detail // .message // .' 2>/dev/null | head -1)"
        fi
        return 1
    fi
}

# Record start time
START_TIME=$(date +%s)

echo -e "${BOLD}${BLUE}Starting direct upload job submission...${NC}"
echo ""

# Submit jobs in parallel batches
SUBMITTED=0
FAILED=0

for ((i=1; i<=NUM_JOBS; i+=$PARALLEL_JOBS)); do
    # Calculate batch size (handle last batch)
    BATCH_END=$((i + PARALLEL_JOBS - 1))
    if [ $BATCH_END -gt $NUM_JOBS ]; then
        BATCH_END=$NUM_JOBS
    fi
    
    echo -e "${CYAN}Submitting batch: jobs $i-$BATCH_END (direct upload)${NC}"
    
    # Launch parallel jobs
    for ((j=i; j<=BATCH_END; j++)); do
        submit_job_direct $j &
    done
    
    # Wait for batch to complete
    wait
    
    # Small pause between batches to avoid overwhelming the API
    if [ $BATCH_END -lt $NUM_JOBS ]; then
        sleep 1  # Increased pause for better reliability
    fi
    
    # Extra pause every 100 jobs to let system stabilize
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
echo -e "${GREEN}✅ Direct Upload Submission Complete!${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Results:${NC}"
echo -e "  • Jobs submitted: ${BOLD}$TOTAL_SUBMITTED/$NUM_JOBS${NC}"
echo -e "  • Time taken: ${BOLD}${DURATION}s${NC}"
echo -e "  • Submission rate: ${BOLD}$(echo "scale=2; $TOTAL_SUBMITTED / $DURATION" | bc) jobs/sec${NC}"
echo -e "  • Method: ${BOLD}Direct blob upload (50% faster)${NC}"
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