# Google Cloud Workstations CLI

Shell scripts to manage Google Cloud Workstations and custom container images from the command line.

## Features

### Workstation Management (`wks.sh`)
- **Start** - Start an existing workstation
- **Stop** - Stop a running workstation
- **Restart** - Restart a workstation
- **Create** - Create a new workstation
- **Delete** - Delete a workstation
- **SSH** - SSH into a running workstation
- **Status** - Check workstation status
- **List** - List all workstations

### Custom Image Management (`wks-image.sh`)
- **Scaffold** - Generate a Dockerfile from predefined base images
- **Build** - Build images locally (Docker) or remotely (Cloud Build)
- **Push** - Push images to Artifact Registry
- **Update-config** - Update workstation config to use a custom image
- **Deploy** - Build + Push + Update in one command
- **List** - List images in the registry
- **Multi-arch** - Support for amd64, arm64, or both

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud` CLI) installed and authenticated
- [Docker](https://docs.docker.com/get-docker/) (for local image builds)
- Docker Buildx (for multi-architecture builds)
- An existing Cloud Workstations cluster and configuration

## Installation

1. Clone or download this repository:
   ```bash
   git clone <repository-url>
   cd google-cloud-wks
   ```

2. Make the scripts executable:
   ```bash
   chmod +x wks.sh wks-image.sh
   ```

3. (Optional) Add to your PATH:
   ```bash
   export PATH="$PATH:$(pwd)"
   ```

## Configuration

### Environment Variables

Copy and configure the example configuration file:

```bash
cp config.example.sh config.sh
# Edit config.sh with your values
```

> **Note:** Both scripts automatically source `config.sh` from the same directory as the script. No need to manually run `source config.sh`.

### Available Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `WORKSTATION_CLUSTER` | Cluster name | Yes |
| `WORKSTATION_CONFIG` | Configuration name | Yes |
| `WORKSTATION_REGION` | GCP region | Yes |
| `WORKSTATION_PROJECT` | GCP project ID | No (uses gcloud default) |
| `WORKSTATION_IMAGE_NAME` | Custom image name | For image builds |
| `WORKSTATION_IMAGE_TAG` | Image tag | For image builds |
| `WORKSTATION_PLATFORMS` | Target architectures | For image builds |
| `WORKSTATION_AR_LOCATION` | Artifact Registry location | For image builds |
| `WORKSTATION_AR_REPOSITORY` | Artifact Registry repo | For image builds |
| `WORKSTATION_BUILD_METHOD` | `local` or `cloud` | For image builds |

---

# Workstation Management

## Quick Start

```bash
# Set up configuration (one-time setup)
cp config.example.sh config.sh
# Edit config.sh with your cluster, config, and region

# Create and use a workstation
./wks.sh create my-workstation
./wks.sh ssh my-workstation

# Stop when done
./wks.sh stop my-workstation
```

## Commands

### Start a Workstation

```bash
./wks.sh start my-workstation
```

The script waits for the workstation to reach RUNNING state and displays the access URL.

### Stop a Workstation

```bash
./wks.sh stop my-workstation
```

### Create a New Workstation

```bash
./wks.sh create my-new-workstation
```

### Delete a Workstation

```bash
./wks.sh delete my-workstation
```

The script will prompt for confirmation before deleting.

### SSH into a Workstation

```bash
./wks.sh ssh my-workstation
```

If the workstation is not running, it will offer to start it first.

### Check Status

```bash
./wks.sh status my-workstation
```

### List All Workstations

```bash
./wks.sh list
```

## Options

| Flag | Description |
|------|-------------|
| `-c, --cluster` | Cluster name |
| `-f, --config` | Configuration name |
| `-r, --region` | GCP region |
| `-p, --project` | Project ID |
| `-v, --verbose` | Show commands being executed |
| `--dry-run` | Show commands without executing |
| `-h, --help` | Show help |

---

# Custom Image Management

## Quick Start

```bash
# 1. Generate a Dockerfile
./wks-image.sh scaffold --base code-oss

# 2. Customize the Dockerfile
vim Dockerfile

# 3. Build, push, and update config in one step
./wks-image.sh deploy --tag v1.0.0
```

## Commands

### Scaffold a Dockerfile

Generate a Dockerfile based on a predefined Cloud Workstations base image:

```bash
# Using VS Code OSS base (default)
./wks-image.sh scaffold

# Using a specific base image
./wks-image.sh scaffold --base intellij

# Specify output path
./wks-image.sh scaffold --base pycharm -o ./custom/Dockerfile
```

#### Available Base Images

| Name | Description |
|------|-------------|
| `code-oss` | VS Code OSS (default) |
| `base` | Minimal base image |
| `intellij` | IntelliJ IDEA Ultimate |
| `pycharm` | PyCharm Professional |
| `webstorm` | WebStorm |
| `goland` | GoLand |
| `clion` | CLion |
| `rider` | Rider |
| `phpstorm` | PHPStorm |
| `rubymine` | RubyMine |

### Build an Image

#### Local Build (Docker)

```bash
# Single architecture (amd64)
./wks-image.sh build --local --platform amd64

# Multi-architecture (requires buildx)
./wks-image.sh build --local --platform amd64,arm64
```

#### Cloud Build

```bash
# Single architecture
./wks-image.sh build --cloud --platform amd64

# Multi-architecture
./wks-image.sh build --cloud --platform amd64,arm64
```

#### Build Options

| Flag | Description |
|------|-------------|
| `--local` | Build with Docker (default) |
| `--cloud` | Build with Cloud Build |
| `--platform` | Target: `amd64`, `arm64`, or `amd64,arm64` |
| `--no-cache` | Build without cache |
| `-t, --tag` | Image tag |
| `-f, --file` | Dockerfile path |

### Push an Image

Push a locally built image to Artifact Registry:

```bash
./wks-image.sh push --tag v1.0.0
```

> **Note:** Multi-arch builds with `--local` and Cloud Build automatically push during the build step.

### Update Workstation Config

Update your workstation configuration to use the custom image:

```bash
./wks-image.sh update-config --tag v1.0.0
```

> **Note:** Existing workstations will use the new image on next restart.

### Deploy (All-in-One)

Build, push, and update configuration in a single command:

```bash
# Local build + push + update
./wks-image.sh deploy --local --platform amd64 --tag v1.0.0

# Cloud Build (multi-arch) + update
./wks-image.sh deploy --cloud --platform amd64,arm64 --tag v1.0.0
```

### List Images

List all images in your Artifact Registry repository:

```bash
./wks-image.sh list
```

## Multi-Architecture Builds

### Local with Docker Buildx

For multi-arch builds, Docker Buildx is required:

```bash
# Enable buildx (if not already enabled)
docker buildx create --name workstation-builder --use

# Build for both architectures
./wks-image.sh build --local --platform amd64,arm64 --tag v1.0.0
```

### Cloud Build

Cloud Build handles multi-arch builds automatically using Kaniko:

```bash
./wks-image.sh build --cloud --platform amd64,arm64 --tag v1.0.0
```

This creates separate images for each architecture and a manifest list that Docker uses to pull the correct image.

---

# Examples

## Complete Workflow

```bash
# 1. Configure (one-time setup - scripts auto-source config.sh)
cp config.example.sh config.sh
vim config.sh  # Set your cluster, config, region

# 2. Create a custom image
./wks-image.sh scaffold --base code-oss
vim Dockerfile  # Customize as needed
./wks-image.sh deploy --cloud --platform amd64 --tag v1.0.0

# 3. Create and use a workstation with the custom image
./wks.sh create dev-workstation
./wks.sh ssh dev-workstation

# 4. When done
./wks.sh stop dev-workstation
```

## Script Integration

Both scripts are designed to work together seamlessly:

| Shared Variable | Used By | Purpose |
|-----------------|---------|---------|
| `WORKSTATION_CLUSTER` | Both | Target workstation cluster |
| `WORKSTATION_CONFIG` | Both | Workstation configuration name |
| `WORKSTATION_REGION` | Both | GCP region |
| `WORKSTATION_PROJECT` | Both | GCP project ID |

### Typical Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Custom Image Development                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. ./wks-image.sh scaffold --base code-oss                                 │
│                          ↓                                                  │
│  2. Edit Dockerfile (add tools, configs)                                    │
│                          ↓                                                  │
│  3. ./wks-image.sh deploy --tag v1.0.0                                      │
│     (builds, pushes, updates config)                                        │
│                          ↓                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                          Workstation Usage                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  4. ./wks.sh create my-workstation                                          │
│     (uses the custom image from step 3)                                     │
│                          ↓                                                  │
│  5. ./wks.sh ssh my-workstation                                             │
│                          ↓                                                  │
│  6. ./wks.sh stop my-workstation                                            │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                          Image Updates                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  7. Edit Dockerfile (make changes)                                          │
│                          ↓                                                  │
│  8. ./wks-image.sh deploy --tag v1.1.0                                      │
│                          ↓                                                  │
│  9. ./wks.sh restart my-workstation                                         │
│     (applies the new image)                                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Quick Update Cycle

After modifying your Dockerfile, apply changes with:

```bash
# Build and deploy new image
./wks-image.sh deploy --tag v1.1.0

# Restart workstation to use new image
./wks.sh restart my-workstation
```

## CI/CD Integration

```bash
#!/bin/bash
# Example CI/CD script

export WORKSTATION_PROJECT="my-project"
export WORKSTATION_CLUSTER="my-cluster"
export WORKSTATION_CONFIG="my-config"
export WORKSTATION_REGION="us-central1"
export WORKSTATION_IMAGE_NAME="team-workstation"
export WORKSTATION_AR_LOCATION="us-central1"
export WORKSTATION_AR_REPOSITORY="workstations"

# Build with version tag
VERSION=$(git describe --tags --always)
./wks-image.sh deploy \
    --cloud \
    --platform amd64,arm64 \
    --tag "$VERSION"
```

---

# Troubleshooting

## "gcloud CLI is not installed"

Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install

## "Docker is not installed"

Install Docker: https://docs.docker.com/get-docker/

## "Docker buildx is not available"

Enable buildx:
```bash
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap
```

## "Cluster/Config/Region is required"

Set environment variables or use CLI flags:
```bash
export WORKSTATION_CLUSTER="your-cluster"
export WORKSTATION_CONFIG="your-config"
export WORKSTATION_REGION="your-region"
```

## Finding Your Resources

```bash
# List clusters
gcloud workstations clusters list --region=us-central1

# List configurations
gcloud workstations configs list \
    --cluster=my-cluster \
    --region=us-central1

# List workstations
gcloud workstations list \
    --cluster=my-cluster \
    --config=my-config \
    --region=us-central1
```

---

## File Structure

```
google-cloud-wks/
├── wks.sh                  # Workstation management script
├── wks-image.sh            # Custom image management script
├── Dockerfile.example      # Example Dockerfile template
├── config.example.sh       # Configuration template
├── config.sh               # Your settings (created from template)
├── scripts/                # Startup scripts for custom images
│   └── 120-install-extensions.sh
├── quickstart.txt          # Quick reference guide
├── developer_guide.md      # Detailed development documentation
├── .gitignore              # Git ignore rules
├── LICENSE                 # MIT License
└── README.md               # This documentation
```

## License

MIT License