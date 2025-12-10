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
    # Try installing Ubuntu prevents launching immediately
    wsl --install -d Ubuntu --no-launch
} catch {
    $err = $_.Exception.Message
    if ($err -match "WSL_E_WSL_OPTIONAL_COMPONENT_REQUIRED") {
        Write-Host "Create Error: WSL Optional Component is missing." -ForegroundColor Red
        Write-Host "You MUST restart your computer to enable WSL features." -ForegroundColor Red
        Write-Host "Please restart and run this script again." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "WSL might already be installed or another error occurred." -ForegroundColor Gray
    Write-Host "Attempting to update/install Ubuntu..." -ForegroundColor Gray
    try {
        wsl --install -d Ubuntu --no-launch
    } catch {
        Write-Host "Standard install failed. Trying without --no-launch..." -ForegroundColor Gray
        wsl --install -d Ubuntu
    }
}

# --- 3. Enable Systemd (Critical) ---
Write-Host "[3/6] Enabling Systemd in Ubuntu..." -ForegroundColor Yellow
# We wait a moment for the distro to register
Start-Sleep -Seconds 5

# Check if we can actually run WSL commands (implies components are ready)
# Check if we can actually run WSL commands (implies components are ready)
$checkOutput = wsl -d Ubuntu -u root -e id 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    if ($checkOutput -match "WSL_E_WSL_OPTIONAL_COMPONENT_REQUIRED" -or $checkOutput -match "Wsl/WSL_E_WSL_OPTIONAL_COMPONENT_REQUIRED") {
        Write-Host "Error: Windows Subsystem for Linux Optional Component is not fully active." -ForegroundColor Red
        Write-Host "System restart is REQUIRED." -ForegroundColor Red
        Write-Host "Please restart your computer and run this script again." -ForegroundColor Yellow
        exit 1
    }
}

try {
    wsl -d Ubuntu -u root -e bash -c "echo -e '[boot]\nsystemd=true' > /etc/wsl.conf"
    Write-Host "Systemd enabled." -ForegroundColor Green
} catch {
    Write-Host "Failed to configure wsl.conf. Is Ubuntu installed?" -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Gray
    exit 1
}

# --- 4. Set Default Distro ---
Write-Host "[4/6] Setting Ubuntu as default..." -ForegroundColor Yellow
try {
    wsl --set-default Ubuntu
} catch {
    Write-Host "Failed to set default distro. Continuing..." -ForegroundColor Gray
}

# --- 5. Create Auto-Start Task ---
Write-Host "[5/6] Creating Background Auto-Start Task..." -ForegroundColor Yellow
$TaskName = "WSL_K3s_AutoStart"
$Command = "wsl.exe -d Ubuntu -u root -e sh -c 'nohup /usr/bin/sleep infinity > /dev/null 2>&1 &'"

# Check if task exists before deleting to avoid error
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    schtasks /delete /tn $TaskName /f 2>$null
}
schtasks /create /tn $TaskName /tr $Command /sc onlogon /rl highest /f /it | Out-Null
Write-Host "Task '$TaskName' created." -ForegroundColor Green

# --- 6. Restart WSL ---
Write-Host "[6/6] Restarting WSL to apply changes..." -ForegroundColor Yellow
wsl --shutdown

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Green
Write-Host "Now, open your specific distribution (type 'wsl') and run the Linutil Worker Setup:"
Write-Host "  curl -fsSL https://raw.githubusercontent.com/rahuljangirwork/linutil/main/core/tabs/system-setup/wsl/wsl-k3s-worker-setup.sh | sudo bash" -ForegroundColor Cyan
