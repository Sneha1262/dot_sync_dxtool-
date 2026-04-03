#!/bin/bash
# Removes the auto-start registration and stops all containers.
# Run: bash scripts/uninstall.sh

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== DX Sync Platform — Uninstall ==="

# Stop containers
echo "Stopping containers..."
cd "$PROJECT_DIR"
docker compose down

# Remove auto-start registration
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLIST_PATH="$HOME/Library/LaunchAgents/com.dx-sync-platform.plist"
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Removed launchd entry."

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo systemctl disable dx-sync-platform 2>/dev/null || true
    sudo systemctl stop dx-sync-platform 2>/dev/null || true
    sudo rm -f /etc/systemd/system/dx-sync-platform.service
    sudo systemctl daemon-reload
    echo "Removed systemd service."
fi

echo ""
echo "=== Done ==="
echo "DX Sync Platform has been stopped and unregistered from auto-start."
