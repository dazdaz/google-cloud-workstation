#!/bin/bash
#
# Google Cloud Workstations Custom Image Management Script
#
# A utility script to build, push, and manage custom container images
# for Google Cloud Workstations.
#
# Supports: scaffold, build, push, update-config, deploy, and list operations.
# Features: Local Docker, Cloud Build, multi-architecture (amd64/arm64)
#

set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration file if it exists
if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    source "${SCRIPT_DIR}/config.sh"
fi

# Colors for output (using $'...' for proper escape sequence interpretation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m' # No Color

# Default values from environment variables
IMAGE_NAME="${WORKSTATION_IMAGE_NAME:-custom-workstation}"
IMAGE_TAG="${WORKSTATION_IMAGE_TAG:-latest}"
DOCKERFILE="${WORKSTATION_DOCKERFILE:-./Dockerfile}"
PLATFORMS="${WORKSTATION_PLATFORMS:-amd64}"
AR_LOCATION="${WORKSTATION_AR_LOCATION:-us-central1}"
AR_REPOSITORY="${WORKSTATION_AR_REPOSITORY:-workstations}"
BUILD_METHOD="${WORKSTATION_BUILD_METHOD:-cloud}"
CLOUD_BUILD_MACHINE="${WORKSTATION_CLOUD_BUILD_MACHINE:-E2_HIGHCPU_32}"
PROJECT="${WORKSTATION_PROJECT:-}"
DRY_RUN=false
VERBOSE=false
CLUSTER="${WORKSTATION_CLUSTER:-}"
CONFIG="${WORKSTATION_CONFIG:-}"
REGION="${WORKSTATION_REGION:-}"

# Script name for help messages
SCRIPT_NAME=$(basename "$0")

# Base images registry
BASE_IMAGES_REGISTRY="us-central1-docker.pkg.dev/cloud-workstations-images/predefined"

# Get base image path for a given short name
# Compatible with bash 3.2 (macOS default)
get_base_image() {
    local name="$1"
    case "$name" in
        code-oss)   echo "code-oss:latest" ;;
        base)       echo "base:latest" ;;
        intellij)   echo "intellij-ultimate:latest" ;;
        pycharm)    echo "pycharm:latest" ;;
        webstorm)   echo "webstorm:latest" ;;
        goland)     echo "goland:latest" ;;
        clion)      echo "clion:latest" ;;
        rider)      echo "rider:latest" ;;
        phpstorm)   echo "phpstorm:latest" ;;
        rubymine)   echo "rubymine:latest" ;;
        *)          echo "" ;;
    esac
}

# List all available base images
list_base_images() {
    echo "code-oss base intellij pycharm webstorm goland clion rider phpstorm rubymine"
}

# =============================================================================
# Helper Functions
# =============================================================================

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_step() {
    echo -e "${CYAN}→${NC} $1"
}

# Get the full registry path
get_registry_path() {
    local project="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    echo "${AR_LOCATION}-docker.pkg.dev/${project}/${AR_REPOSITORY}"
}

# Get the full image URI
get_image_uri() {
    local tag="${1:-$IMAGE_TAG}"
    echo "$(get_registry_path)/${IMAGE_NAME}:${tag}"
}

# Show usage information
show_help() {
    cat << EOF
${BLUE}Google Cloud Workstations Custom Image Management${NC}

${YELLOW}USAGE:${NC}
    $SCRIPT_NAME <command> [options]

${YELLOW}COMMANDS:${NC}
    scaffold        Generate a Dockerfile from a base image
    build           Build the container image
    push            Push the image to Artifact Registry
    update-config   Update workstation config to use the image
    deploy          Build, push, and update config in one step
    list            List images in the registry

${YELLOW}SCAFFOLD OPTIONS:${NC}
    -b, --base <name>        Base image to use (default: code-oss)
    -o, --output <path>      Output Dockerfile path (default: ./Dockerfile)

    Available base images:
      code-oss    - VS Code OSS (default)
      base        - Minimal base image
      intellij    - IntelliJ IDEA Ultimate
      pycharm     - PyCharm Professional
      webstorm    - WebStorm
      goland      - GoLand
      clion       - CLion
      rider       - Rider
      phpstorm    - PHPStorm
      rubymine    - RubyMine

${YELLOW}BUILD OPTIONS:${NC}
    --local                  Build locally with Docker
    --cloud                  Build with Google Cloud Build (default)
    --platform <arch>        Target platform(s): amd64, arm64, or amd64,arm64
    --no-cache               Build without using cache
    -t, --tag <tag>          Image tag (default: latest)
    -f, --file <path>        Dockerfile path (default: ./Dockerfile)

${YELLOW}PUSH OPTIONS:${NC}
    -t, --tag <tag>          Image tag to push (default: latest)

${YELLOW}UPDATE-CONFIG OPTIONS:${NC}
    -t, --tag <tag>          Image tag to use (default: latest)
    -c, --cluster <name>     Workstation cluster name
    --config <name>          Workstation configuration name
    -r, --region <region>    GCP region

${YELLOW}GENERAL OPTIONS:${NC}
    -p, --project <id>       GCP project ID
    -n, --name <name>        Image name (default: custom-workstation)
    --ar-location <loc>      Artifact Registry location (default: us-central1)
    --ar-repo <name>         Artifact Registry repository (default: workstations)
    -v, --verbose            Show commands being executed
    --dry-run                Show commands without executing
    -h, --help               Show this help message

${YELLOW}ENVIRONMENT VARIABLES:${NC}
    WORKSTATION_IMAGE_NAME      Default image name
    WORKSTATION_IMAGE_TAG       Default image tag
    WORKSTATION_DOCKERFILE      Default Dockerfile path
    WORKSTATION_PLATFORMS       Default platforms (amd64,arm64)
    WORKSTATION_AR_LOCATION     Artifact Registry location
    WORKSTATION_AR_REPOSITORY   Artifact Registry repository name
    WORKSTATION_BUILD_METHOD    Default build method (local/cloud)
    WORKSTATION_CLOUD_BUILD_MACHINE  Cloud Build machine type (E2_HIGHCPU_32)
    WORKSTATION_PROJECT         GCP project ID
    WORKSTATION_CLUSTER         Workstation cluster name
    WORKSTATION_CONFIG          Workstation configuration name
    WORKSTATION_REGION          Workstation region

${YELLOW}EXAMPLES:${NC}
    # Generate a Dockerfile based on VS Code
    $SCRIPT_NAME scaffold --base code-oss

    # Build locally for amd64
    $SCRIPT_NAME build --local --platform amd64

    # Build multi-arch with Cloud Build
    $SCRIPT_NAME build --cloud --platform amd64,arm64

    # Push to Artifact Registry
    $SCRIPT_NAME push --tag v1.0.0

    # Update workstation config to use the image
    $SCRIPT_NAME update-config --tag v1.0.0

    # Do everything in one step
    $SCRIPT_NAME deploy --cloud --platform amd64,arm64 --tag v1.0.0

    # List images in registry
    $SCRIPT_NAME list

EOF
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker."
        exit 1
    fi
}

# Check if gcloud is installed
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install the Google Cloud SDK."
        exit 1
    fi
}

# Check if docker buildx is available
check_buildx() {
    if ! docker buildx version &> /dev/null; then
        print_error "Docker buildx is not available. Please install/enable buildx for multi-arch builds."
        exit 1
    fi
}

# Run a command (or show it in dry-run mode)
run_cmd() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY-RUN]${NC} $cmd"
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            echo "${BLUE}[CMD]${NC} $cmd"
        fi
        eval "$cmd"
    fi
}

# Configure Docker for Artifact Registry
configure_docker_auth() {
    print_step "Configuring Docker authentication for Artifact Registry..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY-RUN]${NC} gcloud auth configure-docker ${AR_LOCATION}-docker.pkg.dev --quiet"
        return 0
    fi
    gcloud auth configure-docker "${AR_LOCATION}-docker.pkg.dev" --quiet
}

# Ensure Artifact Registry repository exists
ensure_ar_repository() {
    local project="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    
    print_step "Checking Artifact Registry repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY-RUN]${NC} gcloud artifacts repositories describe $AR_REPOSITORY --location=$AR_LOCATION --project=$project"
        print_success "[DRY-RUN] Would check/create repository."
        return 0
    fi
    
    if ! gcloud artifacts repositories describe "$AR_REPOSITORY" \
        --location="$AR_LOCATION" \
        --project="$project" &> /dev/null; then
        
        print_info "Creating Artifact Registry repository '$AR_REPOSITORY'..."
        gcloud artifacts repositories create "$AR_REPOSITORY" \
            --repository-format=docker \
            --location="$AR_LOCATION" \
            --project="$project" \
            --description="Cloud Workstations custom images"
        print_success "Repository created."
    else
        print_success "Repository exists."
    fi
}

# =============================================================================
# Command Implementations
# =============================================================================

# Scaffold a new Dockerfile
cmd_scaffold() {
    local base_image="code-oss"
    local output_path="./Dockerfile"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--base)
                base_image="$2"
                shift 2
                ;;
            -o|--output)
                output_path="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate base image
    local base_image_path
    base_image_path=$(get_base_image "$base_image")
    if [[ -z "$base_image_path" ]]; then
        print_error "Unknown base image: $base_image"
        echo "Available base images: $(list_base_images)"
        exit 1
    fi
    
    local full_base_image="${BASE_IMAGES_REGISTRY}/${base_image_path}"
    
    print_info "Generating Dockerfile..."
    print_info "  Base image: $base_image"
    print_info "  Output: $output_path"
    
    cat > "$output_path" << EOF
# Google Cloud Workstations Custom Image
# Base: $base_image
# Generated by workstation-image.sh

FROM ${full_base_image}

# Switch to root for installing packages
USER root

# =============================================================================
# System packages
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \\
    curl \\
    git \\
    vim \\
    wget \\
    jq \\
    unzip \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Development tools (uncomment as needed)
# =============================================================================

# Node.js (via nvm)
# ENV NVM_DIR=/home/user/.nvm
# RUN mkdir -p \$NVM_DIR && \\
#     curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && \\
#     . \$NVM_DIR/nvm.sh && \\
#     nvm install --lts && \\
#     nvm use --lts

# Python (additional packages)
# RUN pip3 install --no-cache-dir \\
#     ipython \\
#     jupyter \\
#     black \\
#     flake8

# Go (if not already installed)
# ARG GO_VERSION=1.21.0
# RUN curl -LO https://go.dev/dl/go\${GO_VERSION}.linux-amd64.tar.gz && \\
#     tar -C /usr/local -xzf go\${GO_VERSION}.linux-amd64.tar.gz && \\
#     rm go\${GO_VERSION}.linux-amd64.tar.gz
# ENV PATH=\$PATH:/usr/local/go/bin

# Google Cloud SDK (usually pre-installed, but you can add components)
# RUN gcloud components install kubectl --quiet

# Docker CLI (for Docker-in-Docker scenarios)
# RUN curl -fsSL https://get.docker.com | sh

# =============================================================================
# Custom configurations
# =============================================================================

# Copy custom configuration files
# COPY .bashrc /home/user/.bashrc
# COPY .vimrc /home/user/.vimrc
# COPY settings.json /home/user/.codeoss-cloudworkstations/data/Machine/settings.json

# =============================================================================
# VS Code extensions (for code-oss base)
# =============================================================================
# Extensions must be installed via startup script (code-oss not available during build)
# Create startup script to install extensions on workstation start
RUN echo '#!/bin/bash\\n\\
# Install VS Code extensions\\n\\
# Kilo Code AI Agent - AI coding assistant\\n\\
code-oss-cloud-workstations --install-extension kilocode.Kilo-Code --force\\n\\
# Optional: Additional extensions (uncomment as needed)\\n\\
# code-oss-cloud-workstations --install-extension ms-python.python --force\\n\\
# code-oss-cloud-workstations --install-extension golang.go --force\\n\\
# code-oss-cloud-workstations --install-extension ms-azuretools.vscode-docker --force\\n\\
' > /etc/workstation-startup.d/110-install-extensions.sh \\
    && chmod +x /etc/workstation-startup.d/110-install-extensions.sh

# =============================================================================
# Environment variables
# =============================================================================
# ENV MY_CUSTOM_VAR="value"

# =============================================================================
# Additional startup scripts (optional)
# =============================================================================
# COPY startup.sh /etc/workstation-startup.d/120-custom-startup.sh
# RUN chmod +x /etc/workstation-startup.d/120-custom-startup.sh

# Switch back to the default user (UID 1000 = user in Cloud Workstations base images)
USER 1000

# Set the working directory
WORKDIR /home/user
EOF

    print_success "Dockerfile created at $output_path"
    print_info "Edit the Dockerfile to customize your workstation, then run:"
    echo "    $SCRIPT_NAME build"
}

# Build the container image
cmd_build() {
    local use_cache="--no-cache=false"
    local tag="$IMAGE_TAG"
    local dockerfile="$DOCKERFILE"
    local platforms="$PLATFORMS"
    local method="$BUILD_METHOD"
    local machine_type="$CLOUD_BUILD_MACHINE"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local)
                method="local"
                shift
                ;;
            --cloud)
                method="cloud"
                shift
                ;;
            --platform)
                platforms="$2"
                shift 2
                ;;
            --no-cache)
                use_cache="--no-cache=true"
                shift
                ;;
            -t|--tag)
                tag="$2"
                shift 2
                ;;
            -f|--file)
                dockerfile="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate Dockerfile exists
    if [[ ! -f "$dockerfile" ]]; then
        print_error "Dockerfile not found: $dockerfile"
        print_info "Run '$SCRIPT_NAME scaffold' to generate one."
        exit 1
    fi
    
    local image_uri=$(get_image_uri "$tag")
    
    print_info "Building container image..."
    print_info "  Image: $image_uri"
    print_info "  Dockerfile: $dockerfile"
    print_info "  Platforms: $platforms"
    print_info "  Method: $method"
    
    if [[ "$method" == "cloud" ]]; then
        build_with_cloud_build "$dockerfile" "$image_uri" "$platforms" "$use_cache" "$machine_type"
    else
        build_locally "$dockerfile" "$image_uri" "$platforms" "$use_cache"
    fi
}

# Build locally with Docker/buildx
build_locally() {
    local dockerfile="$1"
    local image_uri="$2"
    local platforms="$3"
    local cache_flag="$4"
    
    check_docker
    configure_docker_auth
    ensure_ar_repository
    
    # Check if multi-arch build
    if [[ "$platforms" == *","* ]]; then
        print_step "Multi-architecture build with docker buildx..."
        check_buildx
        
        # Create/use buildx builder
        if ! docker buildx inspect workstation-builder &> /dev/null; then
            print_step "Creating buildx builder..."
            docker buildx create --name workstation-builder --use
        else
            docker buildx use workstation-builder
        fi
        
        # Build and push multi-arch image
        local platform_flag="linux/${platforms//,/,linux/}"
        
        docker buildx build \
            --platform "$platform_flag" \
            -f "$dockerfile" \
            -t "$image_uri" \
            $cache_flag \
            --push \
            .
        
        print_success "Multi-arch image built and pushed: $image_uri"
    else
        print_step "Single architecture build with docker..."
        
        # Build single arch
        docker build \
            --platform "linux/$platforms" \
            -f "$dockerfile" \
            -t "$image_uri" \
            $cache_flag \
            .
        
        print_success "Image built: $image_uri"
        print_info "Run '$SCRIPT_NAME push' to push the image."
    fi
}

# Build with Cloud Build
build_with_cloud_build() {
    local dockerfile="$1"
    local image_uri="$2"
    local platforms="$3"
    local cache_flag="$4"
    local machine_type="${5:-E2_HIGHCPU_32}"
    
    check_gcloud
    ensure_ar_repository
    
    local project="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    local cloudbuild_file=".cloudbuild-workstation.yaml"
    
    print_info "  Machine type: $machine_type"
    
    # Check if multi-arch build
    if [[ "$platforms" == *","* ]]; then
        print_step "Generating multi-arch Cloud Build configuration..."
        
        # Parse platforms
        IFS=',' read -ra PLATFORM_ARRAY <<< "$platforms"
        
        # Generate Cloud Build config for multi-arch
        cat > "$cloudbuild_file" << EOF
# Auto-generated Cloud Build configuration for multi-architecture build
# Generated by workstation-image.sh

steps:
EOF
        
        # Add build step for each platform
        local image_base="${image_uri%:*}"
        local image_tag="${image_uri##*:}"
        
        for platform in "${PLATFORM_ARRAY[@]}"; do
            local platform_tag="${image_tag}-${platform}"
            cat >> "$cloudbuild_file" << EOF
  # Build for $platform
  - name: 'gcr.io/kaniko-project/executor:latest'
    args:
      - '--dockerfile=${dockerfile}'
      - '--destination=${image_base}:${platform_tag}'
      - '--custom-platform=linux/${platform}'
      - '--cache=true'
      - '--cache-ttl=168h'
EOF
        done
        
        # Add manifest creation step
        cat >> "$cloudbuild_file" << EOF

  # Create multi-arch manifest
  - name: 'gcr.io/cloud-builders/docker'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        docker manifest create ${image_uri} \\
EOF
        
        for platform in "${PLATFORM_ARRAY[@]}"; do
            local platform_tag="${image_tag}-${platform}"
            cat >> "$cloudbuild_file" << EOF
          ${image_base}:${platform_tag} \\
EOF
        done
        
        # Remove trailing backslash and add manifest push
        sed -i.bak '$ s/ \\$//' "$cloudbuild_file" && rm -f "${cloudbuild_file}.bak"
        
        cat >> "$cloudbuild_file" << EOF
        docker manifest push ${image_uri}

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: '${machine_type}'
EOF
        
    else
        print_step "Generating single-arch Cloud Build configuration..."
        
        cat > "$cloudbuild_file" << EOF
# Auto-generated Cloud Build configuration
# Generated by workstation-image.sh

steps:
  - name: 'gcr.io/kaniko-project/executor:latest'
    args:
      - '--dockerfile=${dockerfile}'
      - '--destination=${image_uri}'
      - '--custom-platform=linux/${platforms}'
      - '--cache=true'
      - '--cache-ttl=168h'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: '${machine_type}'
EOF
    fi
    
    print_step "Submitting build to Cloud Build..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY-RUN]${NC} gcloud builds submit --config=$cloudbuild_file --project=$project ."
        echo ""
        echo "${CYAN}Cloud Build config that would be used:${NC}"
        cat "$cloudbuild_file"
        rm -f "$cloudbuild_file"
        return 0
    fi
    
    gcloud builds submit \
        --config="$cloudbuild_file" \
        --project="$project" \
        .
    
    # Cleanup
    rm -f "$cloudbuild_file"
    
    print_success "Image built and pushed: $image_uri"
}

# Push the image to Artifact Registry
cmd_push() {
    local tag="$IMAGE_TAG"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                tag="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    check_docker
    configure_docker_auth
    ensure_ar_repository
    
    local image_uri=$(get_image_uri "$tag")
    
    print_info "Pushing image to Artifact Registry..."
    print_info "  Image: $image_uri"
    
    docker push "$image_uri"
    
    print_success "Image pushed: $image_uri"
}

# Update workstation configuration to use the new image
cmd_update_config() {
    local tag="$IMAGE_TAG"
    local cluster="$CLUSTER"
    local config="$CONFIG"
    local region="$REGION"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                tag="$2"
                shift 2
                ;;
            -c|--cluster)
                cluster="$2"
                shift 2
                ;;
            --config)
                config="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$cluster" ]]; then
        print_error "Cluster name is required. Set WORKSTATION_CLUSTER or use -c flag."
        exit 1
    fi
    if [[ -z "$config" ]]; then
        print_error "Config name is required. Set WORKSTATION_CONFIG or use --config flag."
        exit 1
    fi
    if [[ -z "$region" ]]; then
        print_error "Region is required. Set WORKSTATION_REGION or use -r flag."
        exit 1
    fi
    
    check_gcloud
    
    local image_uri=$(get_image_uri "$tag")
    local project="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    
    print_info "Updating workstation configuration..."
    print_info "  Config: $config"
    print_info "  Cluster: $cluster"
    print_info "  Region: $region"
    print_info "  Image: $image_uri"
    
    # Update the workstation configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY-RUN]${NC} gcloud workstations configs update $config --cluster=$cluster --region=$region --project=$project --container-custom-image=$image_uri"
        return 0
    fi
    
    gcloud workstations configs update "$config" \
        --cluster="$cluster" \
        --region="$region" \
        --project="$project" \
        --container-custom-image="$image_uri"
    
    print_success "Configuration updated to use image: $image_uri"
    print_warning "Note: Existing workstations will use the new image on next restart."
}

# Deploy: build, push, and update config in one step
cmd_deploy() {
    local build_args=()
    local config_args=()
    local tag="$IMAGE_TAG"
    local method="$BUILD_METHOD"
    local platforms="$PLATFORMS"
    
    # Collect all arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                tag="$2"
                build_args+=("$1" "$2")
                config_args+=("$1" "$2")
                shift 2
                ;;
            --local)
                method="local"
                build_args+=("$1")
                shift
                ;;
            --cloud)
                method="cloud"
                build_args+=("$1")
                shift
                ;;
            --platform)
                platforms="$2"
                build_args+=("$1" "$2")
                shift 2
                ;;
            --no-cache|-f|--file)
                if [[ "$1" == "-f" || "$1" == "--file" ]]; then
                    build_args+=("$1" "$2")
                    shift 2
                else
                    build_args+=("$1")
                    shift
                fi
                ;;
            -c|--cluster|--config|-r|--region)
                config_args+=("$1" "$2")
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    print_info "Starting full deployment pipeline..."
    echo ""
    
    # Step 1: Build
    print_info "Step 1/3: Building image..."
    if [[ ${#build_args[@]} -gt 0 ]]; then
        cmd_build "${build_args[@]}"
    else
        cmd_build
    fi
    echo ""
    
    # Step 2: Push (only for local single-arch builds)
    # Cloud builds and multi-arch buildx already push
    if [[ "$method" == "local" ]] && [[ "$platforms" != *","* ]]; then
        print_info "Step 2/3: Pushing image..."
        cmd_push -t "$tag"
        echo ""
    else
        print_info "Step 2/3: Image already pushed during build."
        echo ""
    fi
    
    # Step 3: Update config
    print_info "Step 3/3: Updating workstation configuration..."
    if [[ ${#config_args[@]} -gt 0 ]]; then
        cmd_update_config "${config_args[@]}" -t "$tag"
    else
        cmd_update_config -t "$tag"
    fi
    echo ""
    
    print_success "Deployment complete!"
    print_info "Your workstations will use the new image on next restart."
    echo ""
    print_info "Next steps:"
    echo "    # Restart an existing workstation to use the new image"
    echo "    ./wks.sh restart <workstation-name>"
    echo ""
    echo "    # Or create a new workstation"
    echo "    ./wks.sh create <workstation-name>"
    echo ""
    echo "    # List your workstations"
    echo "    ./wks.sh list"
}

# List images in the registry
cmd_list() {
    check_gcloud
    
    local project="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    local registry_path=$(get_registry_path)
    
    print_info "Listing images in Artifact Registry..."
    print_info "  Registry: $registry_path"
    echo ""
    
    # List all images in the repository
    gcloud artifacts docker images list "$registry_path" \
        --project="$project" \
        --include-tags \
        --format="table(
            package.basename():label=IMAGE,
            version.basename():label=DIGEST,
            tags:label=TAGS,
            createTime.date():label=CREATED
        )"
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    # Parse command (first argument)
    COMMAND="${1:-}"
    shift || true
    
    # Handle help flag first
    if [[ "$COMMAND" == "-h" || "$COMMAND" == "--help" || -z "$COMMAND" ]]; then
        show_help
        exit 0
    fi
    
    # Parse global options that might come before command-specific options
    local args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT="$2"
                shift 2
                ;;
            -n|--name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            --ar-location)
                AR_LOCATION="$2"
                shift 2
                ;;
            --ar-repo)
                AR_REPOSITORY="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Execute the appropriate command
    case "$COMMAND" in
        scaffold)
            if [[ ${#args[@]} -gt 0 ]]; then
                cmd_scaffold "${args[@]}"
            else
                cmd_scaffold
            fi
            ;;
        build)
            if [[ ${#args[@]} -gt 0 ]]; then
                cmd_build "${args[@]}"
            else
                cmd_build
            fi
            ;;
        push)
            if [[ ${#args[@]} -gt 0 ]]; then
                cmd_push "${args[@]}"
            else
                cmd_push
            fi
            ;;
        update-config)
            if [[ ${#args[@]} -gt 0 ]]; then
                cmd_update_config "${args[@]}"
            else
                cmd_update_config
            fi
            ;;
        deploy)
            if [[ ${#args[@]} -gt 0 ]]; then
                cmd_deploy "${args[@]}"
            else
                cmd_deploy
            fi
            ;;
        list)
            if [[ ${#args[@]} -gt 0 ]]; then
                cmd_list "${args[@]}"
            else
                cmd_list
            fi
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

main "$@"