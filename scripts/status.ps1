# Check sync status across all running DX Sync containers.
# Usage: .\scripts\status.ps1

$Containers = @("dev_container_1", "dev_container_2", "dev_container_3")

Write-Host "=== DX Sync Platform — Status ===" -ForegroundColor Cyan
Write-Host ""

$AllOk = $true

foreach ($container in $Containers) {
    # Check if container is running
    $running = docker ps --format "{{.Names}}" | Select-String -Pattern "^$container$"

    if (-not $running) {
        Write-Host "  $container`: NOT RUNNING" -ForegroundColor Red
        $AllOk = $false
        continue
    }

    # Read status file written by the sync agent
    $status = docker exec $container cat /tmp/dx_sync_status 2>$null

    if (-not $status) {
        Write-Host "  $container`: running but no sync recorded yet" -ForegroundColor Yellow
        $AllOk = $false
    } elseif ($status -match "failed") {
        Write-Host "  $container`: $status  <- ATTENTION" -ForegroundColor Red
        $AllOk = $false
    } else {
        # Check staleness — warn if last sync was more than 60 seconds ago
        if ($status -match "(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") {
            $syncTime = [datetime]::ParseExact($matches[1], "yyyy-MM-dd HH:mm:ss", $null)
            $ageSeconds = ([datetime]::UtcNow - $syncTime).TotalSeconds
            if ($ageSeconds -gt 60) {
                Write-Host "  $container`: $status  <- STALE ($([int]$ageSeconds)s ago)" -ForegroundColor Yellow
                $AllOk = $false
            } else {
                Write-Host "  $container`: $status" -ForegroundColor Green
            }
        } else {
            Write-Host "  $container`: $status" -ForegroundColor Green
        }
    }
}

Write-Host ""

if ($AllOk) {
    Write-Host "All containers syncing normally." -ForegroundColor Green
} else {
    Write-Host "One or more containers need attention. Run: docker logs <container_name>" -ForegroundColor Yellow
}
