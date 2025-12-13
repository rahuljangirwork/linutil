# ==============================================================================
# Linutil: Complete WSL Cleanup & Removal Script
# ==============================================================================
# This script completely removes WSL and all configurations
# Features:
# 1. Stops and removes scheduled task
# 2. Terminates all WSL processes
# 3. Unregisters Ubuntu distribution (DELETES ALL DATA!)
# 4. Removes WSL components (kernel, GUI)
# 5. Cleans up configuration files
# 6. Optionally disables Windows features
#
# Usage: Run in PowerShell as Administrator
# ==============================================================================

$ErrorActionPreference = "Stop"
Write-Host "`n=== WSL Complete Removal Script ===" -ForegroundColor Red
Write-Host "⚠️  WARNING: This will DELETE ALL WSL data permanently!" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to cancel, or press Enter to continue..." -ForegroundColor Yellow
Read-Host

# --- 1. Stop and Remove Scheduled Task ---
Write-Host "`n[1/8] Removing Scheduled Task..." -ForegroundColor Cyan
try {
    $task = Get-ScheduledTask -TaskName "WSL_K3s_Worker" -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName "WSL_K3s_Worker" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "WSL_K3s_Worker" -Confirm:$false
        Write-Host "✅ Scheduled task removed." -ForegroundColor Green
    } else {
        Write-Host "   No scheduled task found." -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️  Could not remove scheduled task." -ForegroundColor Yellow
}

# --- 2. Delete VBScript File ---
Write-Host "`n[2/8] Removing VBScript..." -ForegroundColor Cyan
$vbsPath = "$env:USERPROFILE\WSL_Hidden.vbs"
if (Test-Path $vbsPath) {
    Remove-Item $vbsPath -Force
    Write-Host "✅ VBScript removed: $vbsPath" -ForegroundColor Green
} else {
    Write-Host "   No VBScript found." -ForegroundColor Gray
}

# --- 3. Terminate WSL Processes ---
Write-Host "`n[3/8] Shutting down WSL..." -ForegroundColor Cyan
wsl --shutdown
Start-Sleep -Seconds 3
Write-Host "✅ WSL shutdown complete." -ForegroundColor Green

# --- 4. List Distributions Before Removal ---
Write-Host "`n[4/8] Checking installed distributions..." -ForegroundColor Cyan
$rawOutput = wsl -l -q 2>&1 | Out-String
# Split by newlines and clean each line
$distros = $rawOutput -split "`n" | ForEach-Object {
    # Remove null bytes, BOM, and other special chars
    $cleaned = $_ -replace "`0", "" -replace "\uFEFF", "" -replace "[^\x20-\x7E\r\n]", ""
    $cleaned.Trim()
} | Where-Object { 
    $_ -and 
    $_.Length -gt 1 -and
    $_ -notmatch "Windows"
}

if ($distros) {
    Write-Host "Found distributions:" -ForegroundColor Yellow
    $distros | ForEach-Object { Write-Host "   - $_" -ForegroundColor White }
} else {
    Write-Host "   No distributions found." -ForegroundColor Gray
}

# --- 5. Unregister All Distributions ---
Write-Host "`n[5/8] Unregistering distributions (DELETES ALL DATA)..." -ForegroundColor Red
if ($distros) {
    foreach ($distro in $distros) {
        $distroName = $distro.Trim()
        Write-Host "   Removing $distroName..." -ForegroundColor Yellow
        $result = wsl --unregister $distroName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ $distroName removed." -ForegroundColor Green
        } else {
            Write-Host "⚠️  Failed to remove $distroName" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "   No distributions to remove." -ForegroundColor Gray
}

# --- 6. Remove WSL Components ---
Write-Host "`n[6/8] Removing WSL components..." -ForegroundColor Cyan
try {
    # Remove WSL kernel update
    $wslPackage = Get-AppxPackage -Name "*WindowsSubsystemForLinux*"
    if ($wslPackage) {
        Write-Host "   Removing WSL kernel package..." -ForegroundColor Yellow
        $wslPackage | Remove-AppxPackage
        Write-Host "✅ WSL kernel removed." -ForegroundColor Green
    } else {
        Write-Host "   WSL kernel package not found." -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️  Could not remove WSL components." -ForegroundColor Yellow
}

# --- 7. Remove Configuration Files ---
Write-Host "`n[7/8] Removing configuration files..." -ForegroundColor Cyan
$wslConfigPath = "$env:USERPROFILE\.wslconfig"
if (Test-Path $wslConfigPath) {
    Remove-Item $wslConfigPath -Force
    Write-Host "✅ .wslconfig removed: $wslConfigPath" -ForegroundColor Green
} else {
    Write-Host "   No .wslconfig found." -ForegroundColor Gray
}

# --- 8. Optional: Disable Windows Features ---
Write-Host "`n[8/8] Disable Windows Features?" -ForegroundColor Cyan
Write-Host "Do you want to disable WSL Windows features? (y/N)" -ForegroundColor Yellow
Write-Host "(This will require a restart)" -ForegroundColor Gray
$response = Read-Host

if ($response -eq "y" -or $response -eq "Y") {
    Write-Host "   Disabling Windows features..." -ForegroundColor Yellow
    
    try {
        dism.exe /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart
        dism.exe /online /disable-feature /featurename:VirtualMachinePlatform /norestart
        Write-Host "✅ Windows features disabled." -ForegroundColor Green
        Write-Host "⚠️  RESTART REQUIRED to complete removal." -ForegroundColor Red
    } catch {
        Write-Host "⚠️  Could not disable features. Run as Administrator." -ForegroundColor Yellow
    }
} else {
    Write-Host "   Windows features left enabled." -ForegroundColor Gray
}

# --- Summary ---
Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
Write-Host "WSL has been removed from your system." -ForegroundColor White
Write-Host "`nRemoved:" -ForegroundColor Cyan
Write-Host "  ✓ Scheduled task (WSL_K3s_Worker)" -ForegroundColor Gray
Write-Host "  ✓ VBScript file" -ForegroundColor Gray
Write-Host "  ✓ All WSL distributions and data" -ForegroundColor Gray
Write-Host "  ✓ WSL kernel components" -ForegroundColor Gray
Write-Host "  ✓ Configuration files (.wslconfig)" -ForegroundColor Gray
Write-Host "`nDisk space has been freed up." -ForegroundColor Green
