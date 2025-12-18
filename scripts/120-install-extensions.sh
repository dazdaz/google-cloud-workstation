#!/bin/bash
# Install VS Code extensions on workstation startup
# This script runs AFTER Code OSS starts (120 > 110)
# Note: Do NOT use set -e as it can prevent other services from starting

EXTENSIONS_DIR="/home/user/.codeoss-cloudworkstations/extensions"

echo "=== Starting extension installation ==="

# Fix home directory permissions if needed
if [ "$(stat -c '%U' /home/user 2>/dev/null)" != "user" ]; then
    echo "Fixing /home/user ownership..."
    chown -R user:user /home/user/ 2>/dev/null || true
fi

# Create the extensions directory structure if it doesn't exist
if [ ! -d "$EXTENSIONS_DIR" ]; then
    echo "Creating extensions directory..."
    mkdir -p "$EXTENSIONS_DIR"
    chown -R user:user /home/user/.codeoss-cloudworkstations/ 2>/dev/null || true
fi

# Create extensions.json if it doesn't exist
if [ ! -f "$EXTENSIONS_DIR/extensions.json" ]; then
    echo "Creating extensions.json..."
    echo '[]' > "$EXTENSIONS_DIR/extensions.json"
    chown user:user "$EXTENSIONS_DIR/extensions.json" 2>/dev/null || true
fi

echo "Installing VS Code extensions..."

# Kilo Code AI Agent - AI coding assistant
echo "Installing Kilo Code extension..."
code-oss-cloud-workstations --install-extension kilocode.Kilo-Code --force || {
    echo "First attempt failed, retrying in 10 seconds..."
    sleep 10
    code-oss-cloud-workstations --install-extension kilocode.Kilo-Code --force || echo "Warning: Failed to install Kilo Code extension"
}

# Optional: Additional extensions (uncomment as needed)
# code-oss-cloud-workstations --install-extension ms-python.python --force
# code-oss-cloud-workstations --install-extension golang.go --force
# code-oss-cloud-workstations --install-extension ms-azuretools.vscode-docker --force

echo "=== Extension installation complete ==="
code-oss-cloud-workstations --list-extensions