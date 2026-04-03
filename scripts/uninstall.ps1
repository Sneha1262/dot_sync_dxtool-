# Removes the Task Scheduler entry and stops all containers.
# Run: .\scripts\uninstall.ps1

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $PSScriptRoot

Write-Host "=== DX Sync Platform - Uninstall ===" -ForegroundColor Cyan

# Stop containers
Write-Host "Stopping containers..."
Set-Location $ProjectDir
docker compose down

# Remove Task Scheduler task
Unregister-ScheduledTask -TaskName "DXSyncPlatform" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Removed Task Scheduler entry."

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "DX Sync Platform has been stopped and unregistered from auto-start."
