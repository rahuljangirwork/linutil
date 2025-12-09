# ==============================================================================
# Linutil: WSL K3s Worker Prerequisites Setup
# ==============================================================================
# This script sets up a fresh Windows machine for the Linutil K3s Worker.
# It installs WSL, Ubuntu, enables Systemd, and configures auto-start.
#
# Usage: Run in PowerShell as Administrator
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "=== Linutil WSL Setup ===" -ForegroundColor Cyan

# --- 1. Enable Windows Features ---
Write-Host "[1/6] Enabling Windows Features..." -ForegroundColor Yellow
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# --- 2. Install WSL (Ubuntu) ---
Write-Host "[2/6] Installing Ubuntu..." -ForegroundColor Yellow
try {
    wsl --install -d Ubuntu --no-login
} catch {
    Write-Host "WSL might already be installed. Attempting to install/update Ubuntu..." -ForegroundColor Gray
    wsl --install -d Ubuntu --no-login
}

# --- 3. Enable Systemd (Critical) ---
Write-Host "[3/6] Enabling Systemd in Ubuntu..." -ForegroundColor Yellow
# We wait a moment for the distro to register
Start-Sleep -Seconds 5
try {
    wsl -d Ubuntu -u root -e bash -c "echo -e '[boot]\nsystemd=true' > /etc/wsl.conf"
    Write-Host "Systemd enabled." -ForegroundColor Green
} catch {
    Write-Host "Failed to configure wsl.conf. Is Ubuntu installed?" -ForegroundColor Red
    exit 1
}

# --- 4. Set Default Distro ---
Write-Host "[4/6] Setting Ubuntu as default..." -ForegroundColor Yellow
wsl --set-default Ubuntu

# --- 5. Create Auto-Start Task ---
Write-Host "[5/6] Creating Background Auto-Start Task..." -ForegroundColor Yellow
$TaskName = "WSL_K3s_AutoStart"
$Command = "wsl.exe -d Ubuntu -u root -e sh -c 'nohup /usr/bin/sleep infinity > /dev/null 2>&1 &'"
schtasks /delete /tn $TaskName /f 2>$null
schtasks /create /tn $TaskName /tr $Command /sc onlogon /rl highest /f /it | Out-Null
Write-Host "Task '$TaskName' created." -ForegroundColor Green

# --- 6. Restart WSL ---
Write-Host "[6/6] Restarting WSL to apply changes..." -ForegroundColor Yellow
wsl --shutdown

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Green
Write-Host "Now, open your specific distribution (type 'wsl') and run the Linutil Worker Setup:"
Write-Host "  curl -fsSL https://raw.githubusercontent.com/rahuljangirwork/linutil/main/core/tabs/system-setup/wsl/wsl-k3s-worker-setup.sh | sudo bash" -ForegroundColor Cyan
