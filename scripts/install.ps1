# One-time setup script for Windows
# Generates SSH key, builds containers, and registers auto-start via Task Scheduler.
# Run once as Administrator: .\scripts\install.ps1

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $PSScriptRoot
$SshKeyPath = "$env:USERPROFILE\.ssh\dx_sync_key"
$SshKeyPub  = "$SshKeyPath.pub"
$EnvFile    = Join-Path $ProjectDir ".env"

Write-Host "=== DX Sync Platform - One-time Install ===" -ForegroundColor Cyan
Write-Host "Project directory: $ProjectDir"

# Validate .env exists
if (-not (Test-Path $EnvFile)) {
    Write-Host ""
    Write-Host "ERROR: .env file not found." -ForegroundColor Red
    Write-Host "Copy .env.example to .env and fill in your DOTS_REPO_URL first."
    exit 1
}

# Generate SSH key if it doesn't already exist
if (-not (Test-Path $SshKeyPath)) {
    Write-Host ""
    Write-Host "Generating SSH key pair..."
    New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
    ssh-keygen -t ed25519 -C "dx-sync-agent" -f $SshKeyPath -N '""'
    Write-Host "SSH key generated." -ForegroundColor Green
} else {
    Write-Host "SSH key already exists at $SshKeyPath"
}

# Show public key for GitHub
Write-Host ""
Write-Host "=== ACTION REQUIRED ===" -ForegroundColor Yellow
Write-Host "Add this public key to your GitHub account:"
Write-Host "GitHub -> Settings -> SSH and GPG keys -> New SSH key"
Write-Host ""
Get-Content $SshKeyPub
Write-Host ""
Read-Host "Press Enter once you have added the key to GitHub"

# Build and start containers
Write-Host ""
Write-Host "Building and starting containers..."
Set-Location $ProjectDir
docker compose up --build -d
Write-Host "Containers started." -ForegroundColor Green

# Register Task Scheduler task for auto-start on login
Write-Host ""
Write-Host "Registering auto-start on login (Task Scheduler)..."

$TaskName  = "DXSyncPlatform"
$DockerExe = (Get-Command docker).Source

$Action = New-ScheduledTaskAction `
    -Execute $DockerExe `
    -Argument "compose -f `"$(Join-Path $ProjectDir 'docker-compose.yml')`" up -d" `
    -WorkingDirectory $ProjectDir

$Trigger  = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Auto-start DX Sync Platform containers on login" `
    -RunLevel Highest | Out-Null

Write-Host "Registered with Task Scheduler." -ForegroundColor Green

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "DX Sync Platform is running. Check: docker ps"
Write-Host ""
Write-Host "ACTION REQUIRED for full auto-start on reboot:" -ForegroundColor Yellow
Write-Host "  Open Docker Desktop -> Settings -> General"
Write-Host "  Enable 'Start Docker Desktop when you log in'"
Write-Host "  Without this, you will need to open Docker Desktop manually after each reboot."
Write-Host ""
Write-Host "To uninstall: .\scripts\uninstall.ps1"
