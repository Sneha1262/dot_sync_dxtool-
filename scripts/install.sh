#!/bin/bash
# One-time setup script for Linux and macOS
# Generates SSH key, builds containers, and registers auto-start on boot.
# Run once: bash scripts/install.sh

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_KEY="$HOME/.ssh/dx_sync_key"

echo "=== DX Sync Platform — One-time Install ==="
echo "Project directory: $PROJECT_DIR"

# Create .env interactively if it doesn't exist
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo ""
    echo ".env not found — let's set it up now."
    echo ""
    read -p "  DOTS_REPO_URL (e.g. git@github.com:YOUR_USERNAME/dots-repo.git): " dots_url
    default_key="$HOME/.ssh/dx_sync_key"
    read -p "  SSH_KEY_PATH [$default_key]: " ssh_path
    ssh_path="${ssh_path:-$default_key}"

    cat > "$PROJECT_DIR/.env" <<EOF
SSH_KEY_PATH=$ssh_path
DOTS_REPO_URL=$dots_url
DOTS_DIR=/root/dots
SYNC_INTERVAL=15
SYNC_MODE=all
EOF
    echo ".env created at $PROJECT_DIR/.env"
fi

# Generate SSH key if it doesn't exist
if [ ! -f "$SSH_KEY" ]; then
    echo ""
    echo "Generating SSH key pair..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "dx-sync-agent" -f "$SSH_KEY" -N ""
    echo ""
    echo "SSH key generated."
else
    echo "SSH key already exists at $SSH_KEY"
fi

echo ""
echo "=== ACTION REQUIRED ==="
echo "Add this public key to your GitHub account:"
echo "GitHub → Settings → SSH and GPG keys → New SSH key"
echo ""
cat "$SSH_KEY.pub"
echo ""
read -p "Press Enter once you have added the key to GitHub..."

# Build and start containers
echo ""
echo "Building and starting containers..."
cd "$PROJECT_DIR"
docker compose up --build -d
echo "Containers started."

# Register auto-start on boot
echo ""
echo "Registering auto-start on boot..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    PLIST_PATH="$HOME/Library/LaunchAgents/com.dx-sync-platform.plist"
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.dx-sync-platform</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/docker</string>
        <string>compose</string><string>-f</string>
        <string>$PROJECT_DIR/docker-compose.yml</string>
        <string>up</string><string>-d</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>WorkingDirectory</key><string>$PROJECT_DIR</string>
</dict>
</plist>
EOF
    launchctl load "$PLIST_PATH"
    echo "Registered with launchd (macOS)."

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo tee /etc/systemd/system/dx-sync-platform.service > /dev/null <<EOF
[Unit]
Description=DX Sync Platform — dots repo auto-sync
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=$(which docker) compose up -d
ExecStop=$(which docker) compose down
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable dx-sync-platform
    echo "Registered as systemd service (Linux)."
fi

echo ""
echo "=== Done ==="
echo "DX Sync Platform is running. Check: docker ps"
echo ""
echo "ACTION REQUIRED for full auto-start on reboot (macOS/Linux with Docker Desktop):"
echo "  Open Docker Desktop -> Settings -> General"
echo "  Enable 'Start Docker Desktop when you log in'"
echo "  Without this, you will need to open Docker Desktop manually after each reboot."
echo ""
echo "To uninstall: bash scripts/uninstall.sh"
