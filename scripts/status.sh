#!/bin/bash
# Check sync status across all running DX Sync containers.
# Usage: bash scripts/status.sh

CONTAINERS=("dev_container_1" "dev_container_2" "dev_container_3")

echo "=== DX Sync Platform — Status ==="
echo ""

all_ok=true

for container in "${CONTAINERS[@]}"; do
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  $container: NOT RUNNING"
        all_ok=false
        continue
    fi

    # Read status file written by the sync agent
    status=$(docker exec "$container" cat /tmp/dx_sync_status 2>/dev/null)

    if [ -z "$status" ]; then
        echo "  $container: running but no sync recorded yet"
        all_ok=false
    elif echo "$status" | grep -q "failed"; then
        echo "  $container: $status  ← ATTENTION"
        all_ok=false
    else
        # Check staleness — warn if last sync was more than 60 seconds ago
        sync_time=$(echo "$status" | grep -oP '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
        if [ -n "$sync_time" ]; then
            sync_epoch=$(date -u -d "$sync_time" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$sync_time" +%s 2>/dev/null)
            now_epoch=$(date -u +%s)
            age=$(( now_epoch - sync_epoch ))
            if [ "$age" -gt 60 ]; then
                echo "  $container: $status  ← STALE (${age}s ago)"
                all_ok=false
            else
                echo "  $container: $status"
            fi
        else
            echo "  $container: $status"
        fi
    fi
done

echo ""

if [ "$all_ok" = true ]; then
    echo "All containers syncing normally."
else
    echo "One or more containers need attention. Run: docker logs <container_name>"
fi
