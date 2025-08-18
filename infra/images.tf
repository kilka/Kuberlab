# Docker Image Building
# Ensures images are built and pushed to ACR before Flux starts deploying

resource "null_resource" "build_docker_images" {
  # Rebuild when ACR changes or when we want to force a rebuild
  triggers = {
    acr_id = module.acr.registry_id
    # Uncomment to force rebuild on every apply
    # always_run = timestamp()
  }

  # Ensure ACR exists before building
  depends_on = [
    module.acr,
    module.identity # Need identity for ACR access
  ]

  # Build and push images
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "🔍 Checking for Docker images in ACR..."
      
      # Check if Docker is running
      if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker is not running. Please start Docker and run terraform apply again."
        exit 1
      fi
      
      # Login to ACR
      echo "🔐 Logging into ACR ${module.acr.name}..."
      az acr login --name ${module.acr.name}
      
      # Check and build images
      if ! ${path.module}/../scripts/manage-images.sh check 2>/dev/null; then
        echo "📦 Building and pushing Docker images..."
        ${path.module}/../scripts/manage-images.sh build
      else
        echo "✅ Images already exist in ACR"
      fi
    EOT
    
    interpreter = ["bash", "-c"]
  }
}

# Output to track image build status
output "images_built" {
  value = null_resource.build_docker_images.id != "" ? "Images ready" : "Images pending"
  description = "Status of Docker image building"
}