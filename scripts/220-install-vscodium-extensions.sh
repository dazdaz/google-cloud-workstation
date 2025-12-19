#!/bin/bash
# Install VSCodium extensions on workstation startup
# This script runs AFTER VSCodium starts (220 > 200)
# Note: Do NOT use set -e as it can prevent other services from starting

LOG_FILE="/var/log/vscodium-extensions.log"

# Setup logging
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Starting VSCodium extension installation at $(date) ==="

export HOME=/home/user
export USER=user
export DISPLAY=:99

EXTENSIONS_DIR="/home/user/.vscode-oss/extensions"

# Fix home directory permissions if needed
if [ "$(stat -c '%U' /home/user 2>/dev/null)" != "user" ]; then
    echo "Fixing /home/user ownership..."
    chown -R user:user /home/user/ 2>/dev/null || true
fi

# Create the extensions directory structure if it doesn't exist
if [ ! -d "$EXTENSIONS_DIR" ]; then
    echo "Creating extensions directory..."
    mkdir -p "$EXTENSIONS_DIR"
    chown -R user:user /home/user/.vscode-oss/ 2>/dev/null || true
fi

# Create extensions.json if it doesn't exist
if [ ! -f "$EXTENSIONS_DIR/extensions.json" ]; then
    echo "Creating extensions.json..."
    echo '[]' > "$EXTENSIONS_DIR/extensions.json"
    chown user:user "$EXTENSIONS_DIR/extensions.json" 2>/dev/null || true
fi

# Ensure VSCodium config directory exists
mkdir -p /home/user/.config/VSCodium/User
chown -R user:user /home/user/.config/VSCodium 2>/dev/null || true

# Wait for X display to be available (needed for some extensions)
echo "Waiting for display :99 to be available..."
for i in {1..30}; do
    if xdpyinfo -display :99 >/dev/null 2>&1; then
        echo "Display :99 is available"
        break
    fi
    sleep 1
done

# Function to install extension with retry
install_extension() {
    local ext_id="$1"
    local ext_name="$2"
    
    echo "Installing $ext_name ($ext_id)..."
    
    # Try installation as user (preferred)
    if su - user -c "export DISPLAY=:99 && codium --install-extension $ext_id --force" 2>/dev/null; then
        echo "Successfully installed $ext_name"
        return 0
    fi
    
    echo "First attempt failed, retrying in 10 seconds..."
    sleep 10
    
    # Retry
    if su - user -c "export DISPLAY=:99 && codium --install-extension $ext_id --force" 2>/dev/null; then
        echo "Successfully installed $ext_name (retry)"
        return 0
    fi
    
    echo "WARNING: Failed to install $ext_name extension"
    return 1
}

# Function to install extension from VSIX URL
install_from_vsix() {
    local vsix_url="$1"
    local ext_name="$2"
    local vsix_file="/tmp/${ext_name}.vsix"
    
    echo "Downloading $ext_name from VSIX..."
    if curl -L -o "$vsix_file" "$vsix_url" 2>/dev/null; then
        chown user:user "$vsix_file"
        if su - user -c "export DISPLAY=:99 && codium --install-extension $vsix_file --force" 2>/dev/null; then
            echo "Successfully installed $ext_name from VSIX"
            rm -f "$vsix_file"
            return 0
        fi
    fi
    
    echo "WARNING: Failed to install $ext_name from VSIX"
    rm -f "$vsix_file" 2>/dev/null
    return 1
}

echo ""
echo "=== Installing extensions ==="
echo ""

# ==============================================================================
# Kilo Code AI Agent - AI coding assistant
# Available on Open VSX: https://open-vsx.org/extension/kilocode/kilo-code
# ==============================================================================
echo "--- Kilo Code Extension ---"
echo "Installing from Open VSX registry..."

# Install Kilo Code from Open VSX (kilocode.kilo-code)
if ! install_extension "kilocode.kilo-code" "Kilo Code"; then
    echo "WARNING: Failed to install Kilo Code extension"
    echo "You can install it manually in VSCodium:"
    echo "  1. Open Extensions (Ctrl+Shift+X)"
    echo "  2. Search for 'Kilo Code'"
    echo "  3. Click Install"
fi

# ==============================================================================
# Optional: Additional extensions (uncomment as needed)
# ==============================================================================

# Python extension
# install_extension "ms-python.python" "Python"

# Go extension
# install_extension "golang.go" "Go"

# Docker extension
# install_extension "ms-azuretools.vscode-docker" "Docker"

# GitLens
# install_extension "eamodio.gitlens" "GitLens"

# YAML
# install_extension "redhat.vscode-yaml" "YAML"

# Terraform
# install_extension "hashicorp.terraform" "Terraform"

# ==============================================================================
# List installed extensions
# ==============================================================================
echo ""
echo "=== Extension installation complete ==="
echo ""
echo "Installed extensions:"
su - user -c "codium --list-extensions" 2>/dev/null || echo "(Could not list extensions)"

echo ""
echo "Extension installation finished at $(date)"