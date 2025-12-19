#!/bin/bash
# Start VSCodium with noVNC for Cloud Workstations
# This script provides web access to the full VSCodium desktop application

# Do NOT use set -e as it can prevent other services from starting

LOG_FILE="/var/log/vscodium-startup.log"
DEBUG_LOG="/var/log/vscodium-debug.log"

# Setup logging - ensure user can write to logs
touch "$LOG_FILE" "$DEBUG_LOG"
chown user:user "$LOG_FILE" "$DEBUG_LOG"

# Setup logging - both to file and stdout
exec > >(tee -a "$LOG_FILE") 2>&1

# Debug function for detailed logging
debug_log() {
    echo "[DEBUG $(date '+%H:%M:%S')] $1" | tee -a "$DEBUG_LOG"
}

echo "=== Starting VSCodium with noVNC at $(date) ==="
echo "=== Debug log: $DEBUG_LOG ==="

export HOME=/home/user
export USER=user
export DISPLAY=:99

# Screen resolution - Changed to 1600x900 for better laptop compatibility
# 1920x1080 is often too tall for browser windows with toolbars
SCREEN_WIDTH=1600
SCREEN_HEIGHT=900
SCREEN_DEPTH=24

echo "Configuration:"
echo "  Resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH}"
echo "  Display: $DISPLAY"
echo "  Home: $HOME"

# Fix home directory permissions
chown -R user:user /home/user/ 2>/dev/null || true

# Ensure config directories exist
mkdir -p /home/user/.config/VSCodium/User
mkdir -p /home/user/.vscode-oss/extensions
chown -R user:user /home/user/.config 2>/dev/null || true
chown -R user:user /home/user/.vscode-oss 2>/dev/null || true

# Clean up any stale X locks
echo "Cleaning up stale X locks..."
rm -f /tmp/.X99-lock 2>/dev/null || true
rm -f /tmp/.X11-unix/X99 2>/dev/null || true

# ============================================================================
# Start Xvfb (virtual framebuffer)
# ============================================================================
echo "Starting Xvfb on display :99..."
Xvfb :99 -screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH} -dpi 96 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 3

# Verify Xvfb is running
if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "ERROR: Xvfb failed to start"
    exit 1
fi
echo "Xvfb started (PID: $XVFB_PID)"

# ============================================================================
# Configure and start fluxbox window manager
# ============================================================================
echo "Configuring fluxbox..."
mkdir -p /home/user/.fluxbox
chown user:user /home/user/.fluxbox

# Fluxbox init
cat > /home/user/.fluxbox/init << 'EOF'
session.screen0.toolbar.visible: false
session.screen0.defaultDeco: NONE
session.screen0.workspaces: 1
session.screen0.workspacewarping: false
session.screen0.strftimeFormat: %H:%M
session.menuFile: /home/user/.fluxbox/menu
session.styleFile: /usr/share/fluxbox/styles/Makro
session.configVersion: 13
EOF

# Empty menu
cat > /home/user/.fluxbox/menu << 'EOF'
[begin] (fluxbox)
[end]
EOF

# Fluxbox apps - maximize VSCodium
cat > /home/user/.fluxbox/apps << EOF
[app] (name=codium) (class=VSCodium)
  [Dimensions]  {${SCREEN_WIDTH} ${SCREEN_HEIGHT}}
  [Position]    (UPPERLEFT)   {0 0}
  [Maximized]   {yes}
  [Deco]        {NONE}
  [Layer]       {2}
[end]
[app] (name=.*) (class=.*)
  [Dimensions]  {${SCREEN_WIDTH} ${SCREEN_HEIGHT}}
  [Position]    (UPPERLEFT)   {0 0}
  [Maximized]   {yes}
  [Deco]        {NONE}
[end]
EOF

# Disable fluxbox background
cat > /home/user/.fluxbox/overlay << 'EOF'
background: none
background.pixmap:
EOF

# Create startup file
cat > /home/user/.fluxbox/startup << 'EOF'
#!/bin/bash
exec fluxbox
EOF
chmod +x /home/user/.fluxbox/startup

chown -R user:user /home/user/.fluxbox

echo "Starting fluxbox as user..."
su - user -c "export DISPLAY=:99 && fluxbox -no-toolbar" &
FLUXBOX_PID=$!
sleep 2
echo "Fluxbox started (PID: $FLUXBOX_PID)"

# ============================================================================
# Start x11vnc (Running as USER to fix clipboard permissions)
# ============================================================================
echo "Starting x11vnc on port 5900..."

# Prepare log file for user
touch /var/log/x11vnc.log
chown user:user /var/log/x11vnc.log

su - user -c "x11vnc -display :99 \
    -forever \
    -shared \
    -rfbport 5900 \
    -nopw \
    -xkb \
    -noxdamage \
    -cursor arrow \
    -bg \
    -o /var/log/x11vnc.log"

sleep 2
echo "x11vnc started"

# ============================================================================
# Start autocutsel (Running as USER to sync user clipboard)
# ============================================================================
if which autocutsel >/dev/null 2>&1; then
    echo "Starting autocutsel for clipboard sync..."
    su - user -c "export DISPLAY=:99 && autocutsel -fork"
    su - user -c "export DISPLAY=:99 && autocutsel -selection PRIMARY -fork"
else
    echo "WARNING: autocutsel not found, clipboard sync may be flaky"
fi

# ============================================================================
# Configure VSCodium settings
# ============================================================================
echo "Configuring VSCodium settings..."
cat > /home/user/.config/VSCodium/User/settings.json << 'EOF'
{
    "telemetry.telemetryLevel": "off",
    "workbench.colorTheme": "Default Dark Modern",
    "editor.fontSize": 14,
    "editor.tabSize": 2,
    "editor.formatOnSave": true,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "window.titleBarStyle": "custom",
    "window.menuBarVisibility": "classic",
    "window.zoomLevel": 0,
    "window.newWindowDimensions": "maximized",
    "editor.selectionClipboard": true
}
EOF
chown -R user:user /home/user/.config/VSCodium

# ============================================================================
# Start VSCodium
# ============================================================================
echo "Starting VSCodium..."
su - user -c "export DISPLAY=:99 && export HOME=/home/user && codium --no-sandbox --disable-gpu-sandbox /home/user" &
VSCODIUM_PID=$!
echo "VSCodium launch initiated (PID: $VSCODIUM_PID)"

# ============================================================================
# Configure noVNC
# ============================================================================
NOVNC_DIR="/usr/share/novnc"
sudo rm -f "$NOVNC_DIR/index.html"

# Create a custom noVNC page
# Changes:
# 1. resizeSession: false (prevents resize conflicts)
# 2. CSS flexbox fixes for layout
# 3. Clipboard bar preserved
cat > /tmp/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>VSCodium</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; overflow: hidden; background: #1e1e1e; }
        #screen { 
            width: 100%; 
            height: calc(100% - 36px); 
            display: flex; 
            justify-content: center; 
            align-items: center; 
            overflow: hidden; 
        }
        #status { position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); color: #d4d4d4; font-family: sans-serif; text-align: center; z-index: 1000; }
        #status.hidden { display: none; }
        .spinner { border: 4px solid #333; border-top: 4px solid #0078d4; border-radius: 50%; width: 40px; height: 40px; animation: spin 1s linear infinite; margin: 0 auto 20px; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        #clipboard-bar { position: fixed; bottom: 0; left: 0; right: 0; height: 36px; background: #252526; border-top: 1px solid #3c3c3c; display: flex; align-items: center; padding: 0 8px; gap: 8px; z-index: 1000; }
        #clipboard-bar input { flex: 1; background: #3c3c3c; color: #cccccc; border: 1px solid #555; border-radius: 3px; padding: 6px 10px; font-size: 13px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
        #clipboard-bar input:focus { outline: none; border-color: #0078d4; }
        #clipboard-bar input::placeholder { color: #888; }
        #clipboard-bar button { background: #0e639c; color: #fff; border: none; border-radius: 3px; padding: 6px 14px; font-size: 13px; cursor: pointer; white-space: nowrap; }
        #clipboard-bar button:hover { background: #1177bb; }
        #clipboard-bar .hint { color: #888; font-size: 11px; white-space: nowrap; }
    </style>
</head>
<body>
    <div id="status"><div class="spinner"></div><p>Connecting...</p><p id="error"></p></div>
    <div id="screen"></div>
    <div id="clipboard-bar">
        <span class="hint">Paste:</span>
        <input type="text" id="clipboard-input" placeholder="Cmd+V here, then click Send (or press Enter)">
        <button id="send-btn">Send to VM</button>
        <span class="hint">| Copy: select text in VM, then Cmd+C here</span>
    </div>
    <script type="module">
        import RFB from './core/rfb.js';
        const status = document.getElementById('status'), error = document.getElementById('error'), screen = document.getElementById('screen');
        const clipboardInput = document.getElementById('clipboard-input'), sendBtn = document.getElementById('send-btn');
        let rfb = null;
        
        function sendClipboard() {
            const text = clipboardInput.value;
            if (text && rfb && rfb._rfbConnectionState === 'connected') {
                rfb.clipboardPasteFrom(text);
                clipboardInput.value = '';
                clipboardInput.placeholder = '✓ Sent! Now Ctrl+Shift+V in terminal';
                setTimeout(() => { clipboardInput.placeholder = 'Cmd+V here, then click Send (or press Enter)'; }, 2000);
            }
        }
        
        sendBtn.addEventListener('click', sendClipboard);
        clipboardInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') sendClipboard(); });
        
        function connect() {
            if (rfb) { rfb.disconnect(); rfb = null; }
            const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
            const url = protocol + '//' + location.host + '/websockify';
            
            // resizeSession: false is CRITICAL here to prevent conflicts with Xvfb
            try {
                rfb = new RFB(screen, url, { scaleViewport: true, resizeSession: false, background: '#1e1e1e' });
                rfb.addEventListener('connect', () => {
                    status.classList.add('hidden');
                });
                rfb.addEventListener('disconnect', () => {
                    status.classList.remove('hidden');
                    error.textContent = 'Reconnecting...';
                    setTimeout(connect, 2000);
                });
                rfb.addEventListener('clipboard', (e) => {
                    if (navigator.clipboard && e.detail.text) {
                        navigator.clipboard.writeText(e.detail.text).catch(err => console.warn('Clipboard write failed:', err));
                    }
                });
            } catch (err) { error.textContent = err.message; setTimeout(connect, 2000); }
        }
        
        connect();
    </script>
</body>
</html>
HTMLEOF

sudo cp /tmp/index.html "$NOVNC_DIR/index.html"
sudo chmod 644 "$NOVNC_DIR/index.html"

# ============================================================================
# Start websockify
# ============================================================================
echo "Starting websockify on port 80..."
websockify --web="$NOVNC_DIR" 80 localhost:5900 &
NOVNC_PID=$!

echo "Startup complete at $(date)"
wait $NOVNC_PID