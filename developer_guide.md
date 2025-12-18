# Google Cloud Workstations Developer Guide

This guide documents the development and debugging process for the Cloud Workstations management scripts, including key learnings and troubleshooting information.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Scripts Reference](#scripts-reference)
4. [Custom Image Development](#custom-image-development)
5. [Debugging Guide](#debugging-guide)
6. [Key Learnings](#key-learnings)
7. [Common Issues & Solutions](#common-issues--solutions)

---

## Project Overview

This project provides shell scripts to manage Google Cloud Workstations from the command line, including:

- Starting, stopping, and restarting workstations
- Creating and deleting workstations
- Building and deploying custom container images
- Installing VS Code extensions automatically

### Current Deployment

| Component | Value |
|-----------|-------|
| Workstation | `wks1` |
| Cluster | `ws-cluster` |
| Configuration | `wks-config` |
| Region | `europe-west1` |
| Image | `europe-west1-docker.pkg.dev/daev-playground/workstations/custom-workstation:v1.0.6` |
| URL | https://wks1.cluster-uotzpoq77bccaumf6gy3xw6r6i.cloudworkstations.dev |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Developer Machine                           │
├─────────────────────────────────────────────────────────────────┤
│  wks.sh              - Workstation management commands          │
│  wks-image.sh        - Custom image build & deploy              │
│  config.sh           - Environment configuration                │
│  Dockerfile          - Custom image definition                  │
│  scripts/            - Startup scripts for workstations         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Google Cloud                                 │
├─────────────────────────────────────────────────────────────────┤
│  Cloud Build         - Builds container images with Kaniko      │
│  Artifact Registry   - Stores custom container images           │
│  Cloud Workstations  - Runs workstation VMs                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Scripts Reference

### wks.sh - Workstation Management

```bash
# Start a workstation
./wks.sh start wks1

# Stop a workstation (saves costs when not in use)
./wks.sh stop wks1

# Restart workstation to apply new container image
./wks.sh restart wks1

# Create a new workstation
./wks.sh create wks1

# Delete a workstation
./wks.sh delete wks1

# SSH into workstation
./wks.sh ssh wks1

# Check workstation status
./wks.sh status wks1

# List all workstations
./wks.sh list

# Dry run - show commands without executing
./wks.sh --dry-run start wks1
```

### wks-image.sh - Custom Image Management

```bash
# Generate Dockerfile template
./wks-image.sh scaffold [--base code-oss|base|intellij-ultimate]

# Build image using Cloud Build
./wks-image.sh build --tag v1.0.0

# Push image to Artifact Registry (usually not needed - build already pushes)
./wks-image.sh push --tag v1.0.0

# Update workstation config to use new image
./wks-image.sh update-config --tag v1.0.0

# Full deploy: build + push + update-config
./wks-image.sh deploy --tag v1.0.0

# List images in registry
./wks-image.sh list

# Dry run - show commands without executing
./wks-image.sh --dry-run deploy --tag v1.0.0
```

---

## Custom Image Development

### Dockerfile Structure

```dockerfile
# Base image from Google's predefined images
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Copy startup scripts (run automatically when workstation starts)
COPY --chmod=755 scripts/120-install-extensions.sh /etc/workstation-startup.d/120-install-extensions.sh
```

### Available Base Images

| Image | Description |
|-------|-------------|
| `code-oss` | VS Code-based IDE (default) |
| `base` | Minimal base with no IDE |
| `intellij-ultimate` | JetBrains IntelliJ IDEA |

### Startup Script Naming Convention

Scripts in `/etc/workstation-startup.d/` run in alphanumeric order:

```
000_configure-docker.sh   # Docker configuration
010_add-user.sh           # User setup
020_start-sshd.sh         # SSH daemon
030_customize-environment.sh  # Environment customization
110_start-code-oss.sh     # Code OSS IDE startup
120-install-extensions.sh # Custom extension installation (our script)
```

**Important**: Use `120-` prefix (not `110-`) to ensure our script runs AFTER Code OSS starts. Note that `-` sorts before `_` in ASCII, so `110-` would run before `110_`.

### Extension Installation Script

```bash
#!/bin/bash
# scripts/120-install-extensions.sh

EXTENSIONS_DIR="/home/user/.codeoss-cloudworkstations/extensions"

# Fix home directory permissions if needed
if [ "$(stat -c '%U' /home/user 2>/dev/null)" != "user" ]; then
    chown -R user:user /home/user/
fi

# Create extensions directory structure
if [ ! -d "$EXTENSIONS_DIR" ]; then
    mkdir -p "$EXTENSIONS_DIR"
    chown -R user:user /home/user/.codeoss-cloudworkstations/
fi

# Create extensions.json if missing
if [ ! -f "$EXTENSIONS_DIR/extensions.json" ]; then
    echo '[]' > "$EXTENSIONS_DIR/extensions.json"
    chown user:user "$EXTENSIONS_DIR/extensions.json"
fi

# Install extensions
code-oss-cloud-workstations --install-extension kilocode.Kilo-Code --force
```

---

## Debugging Guide

### Check Workstation Status

```bash
./wks.sh status wks1
```

### Check Startup Script Execution

SSH into the workstation and check:

```bash
# List startup scripts
ls -la /etc/workstation-startup.d/

# Check if our script exists
cat /etc/workstation-startup.d/120-install-extensions.sh

# Check startup logs (if they exist)
ls -la /var/log/workstation-startup.d/
cat /var/log/workstation-startup.d/120-install-extensions.sh.log
```

### Check Extension Installation

```bash
# List installed extensions
code-oss-cloud-workstations --list-extensions

# Check extensions directory
ls -la /home/user/.codeoss-cloudworkstations/extensions/
```

### Manual Extension Installation

```bash
# Create required directory structure
mkdir -p /home/user/.codeoss-cloudworkstations/extensions
echo '[]' > /home/user/.codeoss-cloudworkstations/extensions/extensions.json

# Install extension
code-oss-cloud-workstations --install-extension kilocode.Kilo-Code --force
```

### Check Home Directory Permissions

```bash
ls -la /home/
ls -la /home/user/

# Fix if owned by root
sudo chown -R user:user /home/user/
```

### Check Container Image

```bash
# Verify which image the config is using
gcloud workstations configs describe wks-config \
    --cluster=ws-cluster \
    --region=europe-west1 \
    --format="value(container.image)"
```

---

## Key Learnings

### 1. Startup Script Naming (Critical)

**Problem**: Our script `110-install-extensions.sh` was running BEFORE `110_start-code-oss.sh` because `-` (dash) sorts before `_` (underscore) in ASCII.

**Solution**: Name custom scripts with `120-` prefix to ensure they run after the Code OSS startup scripts.

```bash
# Wrong (runs before Code OSS)
110-install-extensions.sh

# Correct (runs after Code OSS)
120-install-extensions.sh
```

### 2. Home Directory Permissions

**Problem**: `/home/user` was owned by `root:root` instead of `user:user`, preventing Code OSS from creating its configuration directories.

**Solution**: The startup script must fix permissions before installing extensions:

```bash
chown -R user:user /home/user/
```

### 3. Extensions Directory Initialization

**Problem**: `code-oss-cloud-workstations --install-extension` fails with "Unable to resolve nonexistent file" if the extensions directory doesn't exist.

**Solution**: Create the directory structure before installing:

```bash
mkdir -p /home/user/.codeoss-cloudworkstations/extensions
echo '[]' > /home/user/.codeoss-cloudworkstations/extensions/extensions.json
```

### 4. Service Account for Private Images

**Problem**: Workstation config couldn't pull private images from Artifact Registry (403 Forbidden error).

**Solution**: Add a service account to the workstation config:

```bash
gcloud workstations configs update wks-config \
    --cluster=ws-cluster \
    --region=europe-west1 \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com
```

### 5. Kaniko vs Docker Build

**Problem**: Cloud Build uses Kaniko, which has different behavior than Docker:
- Heredoc syntax (`cat <<'EOF'`) may not work correctly
- `USER username` directive fails (use numeric UID instead)
- `images:` section in cloudbuild.yaml causes verification failures (Kaniko already pushes)

**Solution**:
- Use `COPY` instead of generating scripts inline
- Use `USER 1000` instead of `USER user`
- Remove `images:` section from Cloud Build config

### 6. Cloud Build Machine Type

**Problem**: Default Cloud Build machine type is slow for large base images.

**Solution**: Use `E2_HIGHCPU_32` for faster builds:

```yaml
options:
  machineType: 'E2_HIGHCPU_32'
```

---

## Common Issues & Solutions

### Issue: "Unable to forward your request to a backend - Couldn't connect to port 80"

**Cause**: The Code OSS HTTP server isn't starting. Usually caused by Dockerfile issues breaking the base image startup.

**Solution**:
1. Test with Google's default image first
2. Simplify Dockerfile to minimal changes
3. Check if startup scripts have errors

### Issue: Extension installation fails with "Unable to read extensions.json"

**Cause**: Extensions directory not initialized.

**Solution**:
```bash
mkdir -p /home/user/.codeoss-cloudworkstations/extensions
echo '[]' > /home/user/.codeoss-cloudworkstations/extensions/extensions.json
```

### Issue: "bash: history: cannot create: Permission denied"

**Cause**: Home directory owned by root.

**Solution**:
```bash
sudo chown -R user:user /home/user/
```

### Issue: "403 Forbidden" when pulling custom image

**Cause**: No service account configured for accessing Artifact Registry.

**Solution**:
```bash
# Get project number
PROJECT_NUM=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")

# Add service account to config
gcloud workstations configs update wks-config \
    --cluster=ws-cluster \
    --region=europe-west1 \
    --service-account=${PROJECT_NUM}-compute@developer.gserviceaccount.com
```

### Issue: SSH fails with "No server on port 22"

**Cause**: Workstation container isn't starting properly.

**Solution**: 
1. Check if web IDE works first
2. Check container startup logs
3. Verify the custom image works

### Issue: Workstation stuck in STARTING state

**Cause**: Image pull issues or container crash.

**Solution**:
1. Check if image exists in Artifact Registry
2. Verify service account permissions
3. Try with default Google image to isolate the issue

---

## Configuration Reference

### config.sh

```bash
# Workstation settings
export WORKSTATION_CLUSTER="ws-cluster"
export WORKSTATION_CONFIG="wks-config"
export WORKSTATION_REGION="europe-west1"

# Image settings
export WORKSTATION_PROJECT="$(gcloud config get-value project)"
export WORKSTATION_IMAGE_NAME="custom-workstation"
export WORKSTATION_REPOSITORY="workstations"
export WORKSTATION_BUILD_METHOD="cloud"  # 'cloud' or 'local'
```

### gcloud CLI Reference

```bash
# List clusters
gcloud workstations clusters list --region=REGION

# List configurations
gcloud workstations configs list --cluster=CLUSTER --region=REGION

# List workstations
gcloud workstations list --cluster=CLUSTER --config=CONFIG --region=REGION

# Describe workstation
gcloud workstations describe WORKSTATION \
    --cluster=CLUSTER --config=CONFIG --region=REGION

# Describe config
gcloud workstations configs describe CONFIG \
    --cluster=CLUSTER --region=REGION
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | 2024-12-18 | Initial custom image with Kilo Code extension |
| v1.0.1 | 2024-12-18 | Fixed startup script heredoc syntax |
| v1.0.2 | 2024-12-18 | Changed to printf for script generation |
| v1.0.3 | 2024-12-18 | Changed to COPY for startup script |
| v1.0.4 | 2024-12-18 | Minimal Dockerfile (removed apt-get, USER directives) |
| v1.0.5 | 2024-12-18 | Renamed script to 120- prefix, added wait logic |
| v1.0.6 | 2024-12-18 | Added permission fixes and directory creation |