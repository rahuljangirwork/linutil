# ==============================================================================
# Linutil: WSL K3s Worker Prerequisites Setup
# ==============================================================================
# This script sets up a fresh Windows machine for the Linutil K3s Worker.
# Features:
# 1. Enables Windows Features (WSL, Platform)
# 2. Installs Ubuntu (if missing)
# 3. Configures .wslconfig for performance and NON-STOP execution
# 4. Enables Systemd
# 5. Creates a HIDDEN, ROBUST background task to keep WSL alive 24/7
#
# Usage: Run in PowerShell as Administrator
# ==============================================================================

$ErrorActionPreference = "Stop"
Write-Host "`n=== Linutil WSL Setup ===" -ForegroundColor Cyan

# --- 1. Enable Windows Features ---
Write-Host "[1/6] Enabling Windows Features..." -ForegroundColor Yellow
$feat1 = dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
$feat2 = dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Check if reboot is pending from DISM output
if (($feat1 -match "restart") -or ($feat2 -match "restart")) {
    Write-Host "`n⚠️  RESTART REQUIRED ⚠️" -ForegroundColor Red
    Write-Host "Windows features have been enabled."
    Write-Host "You MUST restart your computer now."
    Write-Host "After restarting, run this script again to finish setup."
    exit 0
}

# --- 2. Install WSL (Ubuntu) ---
Write-Host "`n[2/6] Checking Ubuntu Installation..." -ForegroundColor Yellow
if (wsl -l -q 2>&1 | Select-String "Ubuntu") {
    Write-Host "✅ Ubuntu is already installed." -ForegroundColor Green
} else {
    Write-Host "Installing Ubuntu..." -ForegroundColor Cyan
    try {
        wsl --install -d Ubuntu --no-launch
        Write-Host "✅ Ubuntu installed." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Standard install failed. Trying alternatives..." -ForegroundColor Yellow
        # Fallback for systems where --no-launch isn't supported or generic error
        wsl --install -d Ubuntu
    }
}

# Get actual distro name
$DistroName = (wsl -l -v | Where-Object { $_ -match "Run" -or $_ -match "Stop" } | Select-Object -First 1).Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[1]
if (-not $DistroName) { $DistroName = "Ubuntu" }
Write-Host "   Target Distro: $DistroName" -ForegroundColor Gray

# --- 3. Configure .wslconfig (Performance & Keep-Alive) ---
Write-Host "`n[3/6] Configuring .wslconfig (Performance & Keep-Alive)..." -ForegroundColor Yellow
$wslConfigPath = "$env:USERPROFILE\.wslconfig"
$totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$wslConfigContent = @"
[wsl2]
# CRITICAL: Never auto-shutdown (keeps WSL running 24/7)
vmIdleTimeout=-1

# Dynamic memory allocation (up to 80% of ${totalRAM}GB)
memory=80%

# Network (Mirrored is best for K3s/VPNs if supported on Win11, fallback to NAT otherwise)
# firewall=true
# networkingMode=mirrored 

# Performance
nestedVirtualization=true
pageReporting=true
autoMemoryReclaim=gradual
"@
Set-Content -Path $wslConfigPath -Value $wslConfigContent -Force
Write-Host "✅ .wslconfig updated (vmIdleTimeout=-1)." -ForegroundColor Green

# --- 4. Enable Systemd ---
Write-Host "`n[4/6] Enabling Systemd..." -ForegroundColor Yellow
# Wait for WSL to be ready
Start-Sleep -Seconds 5
try {
    # Check if we can run a command
    wsl -d $DistroName -u root -e bash -c "grep -q 'systemd=true' /etc/wsl.conf || echo -e '[boot]\nsystemd=true' >> /etc/wsl.conf"
    Write-Host "✅ Systemd verified." -ForegroundColor Green
} catch {
    Write-Host "⚠️  Could not run WSL command yet. A reboot might effectively be required." -ForegroundColor Yellow
}

# --- 5. Create HIDDEN Background Task ---
Write-Host "`n[5/6] Creating HIDDEN Background Task..." -ForegroundColor Yellow
$TaskName = "WSL_K3s_Worker"

# Delete old tasks
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "WSL_K3s_AutoStart" -Confirm:$false -ErrorAction SilentlyContinue

# New Hidden Task
# Action: Login shell to force boot
$Action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $DistroName --cd / -e bash -l -c 'sleep infinity'"
# Trigger: At Logon (User context)
$Trigger = New-ScheduledTaskTrigger -AtLogon
# Settings: Hidden, Long execution, Restart if fails
$Settings = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Days 0) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -RunLevel Highest -Force | Out-Null
Write-Host "✅ Task '$TaskName' registered (Hidden)." -ForegroundColor Green

# --- 6. Start & Restart ---
Write-Host "`n[6/6] Applying Configuration..." -ForegroundColor Yellow
Write-Host "Shutting down WSL to apply settings..."
wsl --shutdown
Start-Sleep -Seconds 3

Write-Host "Starting Background Task..."
Start-ScheduledTask -TaskName $TaskName

# Verification
Start-Sleep -Seconds 5
if (Get-Process -Name "wsl*" -ErrorAction SilentlyContinue) {
    Write-Host "`n✅ SUCCESS: WSL is running in the background!" -ForegroundColor Green
} else {
    Write-Host "`n⚠️  WSL process not seen yet. It might still be starting." -ForegroundColor Yellow
}

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Cyan
Write-Host "Your WSL instance is configured to run 24/7."
Write-Host "You can now run the Worker Setup script."
Write-Host "  curl -fsSL https://raw.githubusercontent.com/rahuljangirwork/linutil/main/core/tabs/system-setup/wsl/wsl-k3s-worker-setup.sh | sudo bash" -ForegroundColor Cyan
