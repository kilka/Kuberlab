#!/bin/bash
# Script to check and build Docker images for ACR

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_VERSION="v1.0.2"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_ROOT/app"

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_color "$RED" "❌ Docker is not running. Please start Docker Desktop and try again."
        exit 1
    fi
    print_color "$GREEN" "✓ Docker is running"
}

# Function to get ACR name from Terraform
get_acr_name() {
    cd "$PROJECT_ROOT/infra"
    ACR_NAME=$(terraform output -raw acr_name 2>/dev/null || echo "")
    if [ -z "$ACR_NAME" ]; then
        print_color "$RED" "❌ Could not get ACR name from Terraform outputs"
        print_color "$YELLOW" "  Make sure you've run 'terraform apply' first"
        exit 1
    fi
    echo "$ACR_NAME"
}

# Function to login to ACR
login_acr() {
    local acr_name=$1
    print_color "$BLUE" "🔐 Logging into ACR: $acr_name..."
    if az acr login --name "$acr_name" > /dev/null 2>&1; then
        print_color "$GREEN" "✓ Successfully logged into ACR"
        return 0
    else
        print_color "$RED" "❌ Failed to login to ACR"
        return 1
    fi
}

# Function to check if image exists in ACR
check_image_exists() {
    local acr_name=$1
    local image_name=$2
    local version=$3
    
    if az acr repository show-tags --name "$acr_name" --repository "$image_name" 2>/dev/null | grep -q "\"$version\""; then
        return 0
    else
        return 1
    fi
}

# Function to build and push image
build_and_push_image() {
    local acr_name=$1
    local image_name=$2
    local version=$3
    local context_dir=$4
    
    local full_image="${acr_name}.azurecr.io/${image_name}:${version}"
    
    print_color "$BLUE" "🏗️  Building $image_name..."
    
    if docker buildx build \
        --platform linux/amd64,linux/arm64 \
        -t "$full_image" \
        --push \
        "$context_dir" > /dev/null 2>&1; then
        print_color "$GREEN" "✓ Successfully built and pushed $image_name"
        return 0
    else
        print_color "$RED" "❌ Failed to build $image_name"
        return 1
    fi
}

# Main execution based on command
case "${1:-check}" in
    check)
        print_color "$BLUE" "🔍 Checking Docker images in ACR..."
        
        check_docker
        ACR_NAME=$(get_acr_name)
        login_acr "$ACR_NAME"
        
        API_EXISTS=false
        WORKER_EXISTS=false
        
        if check_image_exists "$ACR_NAME" "ocr-api" "$IMAGE_VERSION"; then
            print_color "$GREEN" "✓ ocr-api:$IMAGE_VERSION exists"
            API_EXISTS=true
        else
            print_color "$YELLOW" "⚠ ocr-api:$IMAGE_VERSION not found"
        fi
        
        if check_image_exists "$ACR_NAME" "ocr-worker" "$IMAGE_VERSION"; then
            print_color "$GREEN" "✓ ocr-worker:$IMAGE_VERSION exists"
            WORKER_EXISTS=true
        else
            print_color "$YELLOW" "⚠ ocr-worker:$IMAGE_VERSION not found"
        fi
        
        if [ "$API_EXISTS" = true ] && [ "$WORKER_EXISTS" = true ]; then
            print_color "$GREEN" "✅ All images are present in ACR"
            exit 0
        else
            print_color "$YELLOW" "⚠️  Some images are missing. Run 'make build-images' to build them."
            exit 1
        fi
        ;;
        
    build)
        print_color "$BLUE" "📦 Building and pushing Docker images to ACR..."
        
        check_docker
        ACR_NAME=$(get_acr_name)
        login_acr "$ACR_NAME"
        
        # Check which images need building
        BUILD_API=false
        BUILD_WORKER=false
        
        if ! check_image_exists "$ACR_NAME" "ocr-api" "$IMAGE_VERSION"; then
            BUILD_API=true
        fi
        
        if ! check_image_exists "$ACR_NAME" "ocr-worker" "$IMAGE_VERSION"; then
            BUILD_WORKER=true
        fi
        
        # Build only missing images
        if [ "$BUILD_API" = true ]; then
            build_and_push_image "$ACR_NAME" "ocr-api" "$IMAGE_VERSION" "$APP_DIR/api"
        else
            print_color "$BLUE" "ℹ️  ocr-api:$IMAGE_VERSION already exists, skipping"
        fi
        
        if [ "$BUILD_WORKER" = true ]; then
            build_and_push_image "$ACR_NAME" "ocr-worker" "$IMAGE_VERSION" "$APP_DIR/worker"
        else
            print_color "$BLUE" "ℹ️  ocr-worker:$IMAGE_VERSION already exists, skipping"
        fi
        
        print_color "$GREEN" "✅ Image build complete!"
        ;;
        
    force-build)
        print_color "$BLUE" "📦 Force building and pushing all Docker images..."
        
        check_docker
        ACR_NAME=$(get_acr_name)
        login_acr "$ACR_NAME"
        
        build_and_push_image "$ACR_NAME" "ocr-api" "$IMAGE_VERSION" "$APP_DIR/api"
        build_and_push_image "$ACR_NAME" "ocr-worker" "$IMAGE_VERSION" "$APP_DIR/worker"
        
        print_color "$GREEN" "✅ Force build complete!"
        ;;
        
    *)
        print_color "$RED" "Unknown command: $1"
        echo "Usage: $0 {check|build|force-build}"
        echo "  check       - Check if images exist in ACR"
        echo "  build       - Build and push missing images"
        echo "  force-build - Force rebuild all images"
        exit 1
        ;;
esac