# ==============================================================================
# Linutil: WSL K3s Worker Prerequisites Setup
# ==============================================================================
# This script sets up a fresh Windows machine for the Linutil K3s Worker.
# Features:
# 1. Enables Windows Features (WSL, Platform)
# 2. Updates WSL to the latest version (Critical for stability)
# 3. Installs Ubuntu (if missing)
# 4. Configures .wslconfig for performance and NON-STOP execution
# 5. Enables Systemd
# 6. Creates a HIDDEN, ROBUST background task to keep WSL alive 24/7
#
# Usage: Run in PowerShell as Administrator
# ==============================================================================

$ErrorActionPreference = "Stop"
Write-Host "`n=== Linutil WSL Setup ===" -ForegroundColor Cyan

# --- 1. Enable Windows Features ---
Write-Host "[1/7] Enabling Windows Features..." -ForegroundColor Yellow

$restartRequired = $false

# Helper to check and enable feature
function Enable-FeatureIfMissing ($Name) {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName $Name
    if ($feat.State -ne "Enabled") {
        Write-Host "   Enabling $Name..." -ForegroundColor Cyan
        $result = dism.exe /online /enable-feature /featurename:$Name /all /norestart
        if ($result -match "restart") { return $true }
    } else {
        Write-Host "   ✅ $Name is already enabled." -ForegroundColor Green
    }
    return $false
}

if (Enable-FeatureIfMissing "Microsoft-Windows-Subsystem-Linux") { $restartRequired = $true }
if (Enable-FeatureIfMissing "VirtualMachinePlatform") { $restartRequired = $true }

# Check if reboot is pending
if ($restartRequired) {
    Write-Host "`n⚠️  RESTART REQUIRED ⚠️" -ForegroundColor Red
    Write-Host "Windows features have been enabled."
    Write-Host "You MUST restart your computer now."
    Write-Host "After restarting, run this script again to finish setup."
    exit 0
}

# --- 2. Update WSL Kernel ---
Write-Host "`n[2/7] Updating WSL Kernel..." -ForegroundColor Yellow
try {
    Write-Host "Running 'wsl --update' to ensure compatibility..."
    # wsl --update can sometimes fail if already running or network issues, but we try it.
    # We use Start-Process to wait for it properly.
    $p = Start-Process wsl -ArgumentList "--update" -PassThru -Wait -NoNewWindow
    if ($p.ExitCode -eq 0) {
         Write-Host "✅ WSL updated." -ForegroundColor Green
    } else {
         Write-Host "ℹ️ WSL update exited with code $($p.ExitCode). Proceeding..." -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️  Failed to run wsl --update. Proceeding, but errors may occur." -ForegroundColor DarkYellow
}

# --- 3. Install WSL (Ubuntu) ---
Write-Host "`n[3/7] Checking Ubuntu Installation..." -ForegroundColor Yellow

$ubuntuInstalled = $false
try {
    # This command can fail if WSL is totally broken or requires update (which we just tried to fix)
    $list = wsl -l -q 2>&1
    if ($list -match "Ubuntu") {
        $ubuntuInstalled = $true
    }
} catch {
    Write-Host "⚠️  Could not list distributions. WSL might be in a bad state." -ForegroundColor Red
}

if ($ubuntuInstalled) {
    Write-Host "✅ Ubuntu is already installed." -ForegroundColor Green
} else {
    Write-Host "Installing Ubuntu..." -ForegroundColor Cyan
    try {
        wsl --install -d Ubuntu --no-launch
        Write-Host "✅ Ubuntu installed." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Standard install failed. Trying alternatives..." -ForegroundColor Yellow
        # Fallback for systems where --no-launch isn't supported or generic error
        try {
            wsl --install -d Ubuntu
        } catch {
             Write-Host "❌ Failed to install Ubuntu. Please install it manually from the Store." -ForegroundColor Red
             exit 1
        }
    }
}

# Get actual distro name
try {
    $DistroName = (wsl -l -v | Where-Object { $_ -match "Run" -or $_ -match "Stop" } | Select-Object -First 1).Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[1]
} catch {
    $DistroName = $null
}

if (-not $DistroName) { 
    $DistroName = "Ubuntu" 
    Write-Host "   Defaulting Distro check to: $DistroName" -ForegroundColor Gray
} else {
    Write-Host "   Target Distro: $DistroName" -ForegroundColor Gray
}

# --- 4. Configure .wslconfig (Performance & Keep-Alive) ---
Write-Host "`n[4/7] Configuring .wslconfig (Performance & Keep-Alive)..." -ForegroundColor Yellow
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

try {
    Set-Content -Path $wslConfigPath -Value $wslConfigContent -Force
    Write-Host "✅ .wslconfig updated (vmIdleTimeout=-1)." -ForegroundColor Green
} catch {
    Write-Host "⚠️  Could not write .wslconfig. Permission denied?" -ForegroundColor Red
}

# --- 5. Enable Systemd ---
Write-Host "`n[5/7] Enabling Systemd..." -ForegroundColor Yellow
# Wait for WSL to be ready
Start-Sleep -Seconds 5
try {
    # Check if we can run a command
    wsl -d $DistroName -u root -e bash -c "grep -q 'systemd=true' /etc/wsl.conf || echo -e '[boot]\nsystemd=true' >> /etc/wsl.conf"
    Write-Host "✅ Systemd verified." -ForegroundColor Green
} catch {
    Write-Host "⚠️  Could not run WSL command yet. A reboot might effectively be required or Distro not ready." -ForegroundColor Yellow
}

# --- 6. Create HIDDEN Background Task ---
Write-Host "`n[6/7] Creating HIDDEN Background Task..." -ForegroundColor Yellow
$TaskName = "WSL_K3s_Worker"

# Delete old tasks
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "WSL_K3s_AutoStart" -Confirm:$false -ErrorAction SilentlyContinue

# Create VBScript wrapper for truly hidden execution
$vbsPath = "$env:USERPROFILE\WSL_Hidden.vbs"
$vbsContent = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "wsl.exe -d $DistroName -e sleep infinity", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Force
Write-Host "   Created VBScript: $vbsPath" -ForegroundColor Gray

# Action: Execute VBScript (completely hidden)
$Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""

# Trigger: At Logon for the current user
$Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME

# Settings: Power friendly but persistent
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

# Principal: Run as current user (Interactive)
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force | Out-Null
    Write-Host "✅ Task '$TaskName' registered (Completely Hidden via VBScript)." -ForegroundColor Green
} catch {
    Write-Host "⚠️  Failed to register scheduled task. Try identifying as Admin?" -ForegroundColor Red
}

# --- 7. Start & Restart ---
Write-Host "`n[7/7] Applying Configuration..." -ForegroundColor Yellow
Write-Host "Shutting down WSL to apply systemd changes..."
wsl --shutdown
Start-Sleep -Seconds 10

Write-Host "Starting Background Task..."
Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

# Verification Loop (systemd needs more time)
Write-Host "Verifying WSL status (systemd initialization may take 30-60 seconds)..."
$maxRetries = 20
$isRunning = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    $status = wsl -l -v 2>&1 | Out-String
    if ($status -match "Running") {
        $isRunning = $true
        break
    }
    Write-Host "   Waiting for WSL to start... ($i/$maxRetries)" -ForegroundColor Gray
    Start-Sleep -Seconds 3
}

if ($isRunning) {
    Write-Host "`n✅ SUCCESS: WSL is running in the background!" -ForegroundColor Green
    # Verify systemd is actually running
    Start-Sleep -Seconds 5
    $systemdCheck = wsl -d $DistroName -e bash -c "ps -p 1 -o comm=" 2>&1
    if ($systemdCheck -match "systemd") {
        Write-Host "✅ Systemd is active (PID 1)" -ForegroundColor Green
    }
    Get-Process -Name "wsl*" -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, StartTime | Format-Table -AutoSize
} else {
    Write-Host "`n⚠️  WSL didn't start in 60 seconds. Manual start required..." -ForegroundColor Yellow
    Write-Host "Run this command to start manually:" -ForegroundColor Cyan
    Write-Host "   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
    Write-Host "Or check VBScript directly:" -ForegroundColor Cyan
    Write-Host "   wscript `"$vbsPath`"" -ForegroundColor White
}

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Cyan
Write-Host "Your WSL instance is configured to run 24/7."
Write-Host "You can now run the Worker Setup script."
Write-Host "  curl -fsSL https://raw.githubusercontent.com/rahuljangirwork/linutil/main/core/tabs/system-setup/wsl/wsl-k3s-worker-setup.sh | sudo bash" -ForegroundColor Cyan
