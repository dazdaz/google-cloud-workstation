# Google Cloud Workstations Configuration
#
# Copy this file to config.sh and update with your values:
#   cp config.example.sh config.sh
#
# Then source it before running the scripts:
#   source config.sh
#   ./workstation.sh start my-workstation
#   ./workstation-image.sh build

# =============================================================================
# Workstation Management (workstation.sh)
# =============================================================================

# Required: The name of your workstation cluster
export WORKSTATION_CLUSTER="my-cluster"

# Required: The name of your workstation configuration
export WORKSTATION_CONFIG="my-config"

# Required: The GCP region where your workstation resources are located
export WORKSTATION_REGION="us-central1"

# Optional: GCP Project ID (if not set, uses gcloud default project)
# export WORKSTATION_PROJECT="my-gcp-project"

# =============================================================================
# Custom Image Management (workstation-image.sh)
# =============================================================================

# Image name (without registry path)
export WORKSTATION_IMAGE_NAME="custom-workstation"

# Image tag
export WORKSTATION_IMAGE_TAG="latest"

# Path to your Dockerfile
export WORKSTATION_DOCKERFILE="./Dockerfile"

# Target platforms: amd64, arm64, or amd64,arm64 (for multi-arch)
export WORKSTATION_PLATFORMS="amd64"

# Cloud Build machine type for faster builds
# Options: E2_HIGHCPU_8, E2_HIGHCPU_32, N1_HIGHCPU_8, N1_HIGHCPU_32
export WORKSTATION_CLOUD_BUILD_MACHINE="E2_HIGHCPU_32"

# Artifact Registry location
export WORKSTATION_AR_LOCATION="us-central1"

# Artifact Registry repository name
export WORKSTATION_AR_REPOSITORY="workstations"

# Build method: local (Docker) or cloud (Cloud Build)
export WORKSTATION_BUILD_METHOD="cloud"