# Google Cloud Workstations Configuration
# Source this file before running the scripts:
#   source config.sh

# =============================================================================
# Workstation Management (workstation.sh)
# =============================================================================

# Your workstation cluster name
export WORKSTATION_CLUSTER="ws-cluster"

# Your workstation configuration name
export WORKSTATION_CONFIG="wks-config"

# Your GCP region
export WORKSTATION_REGION="europe-west1"

# GCP Project ID (uses gcloud default if not set)
# export WORKSTATION_PROJECT="daev-playground"

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

# Artifact Registry location (same as region)
export WORKSTATION_AR_LOCATION="europe-west1"

# Artifact Registry repository name
export WORKSTATION_AR_REPOSITORY="workstations"

# Build method: local (Docker) or cloud (Cloud Build)
export WORKSTATION_BUILD_METHOD="cloud"
