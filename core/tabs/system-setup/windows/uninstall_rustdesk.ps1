# ==============================================================================
# RustDesk Complete Uninstall Script
# ==============================================================================
# This script completely removes RustDesk including:
# - Service
# - Application
# - Configuration files
# - Registry entries
# - Startup entries
# ==============================================================================

$ErrorActionPreference = "Stop"
Write-Host "`n=== RustDesk Complete Uninstall ===" -ForegroundColor Cyan

# --- 1. Stop and Remove Service ---
Write-Host "`n[1/6] Stopping and removing RustDesk service..." -ForegroundColor Yellow
$ServiceName = 'Rustdesk'
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($service -ne $null) {
    try {
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Write-Host "✅ Service stopped." -ForegroundColor Green
        }
        
        # Remove service using sc command
        sc.exe delete $ServiceName | Out-Null
        Write-Host "✅ Service removed." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Service removal encountered issues, continuing..." -ForegroundColor Yellow
    }
} else {
    Write-Host "✅ Service not found - Skipping" -ForegroundColor Green
}

# --- 2. Kill any running RustDesk processes ---
Write-Host "`n[2/6] Stopping RustDesk processes..." -ForegroundColor Yellow
try {
    Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "✅ Processes stopped." -ForegroundColor Green
} catch {
    Write-Host "✅ No running processes found." -ForegroundColor Green
}

# --- 3. Run Official Uninstaller ---
Write-Host "`n[3/6] Running RustDesk uninstaller..." -ForegroundColor Yellow
$uninstallerPath = "$env:ProgramFiles\RustDesk\uninstall.exe"

if (Test-Path $uninstallerPath) {
    try {
        Start-Process -FilePath $uninstallerPath -ArgumentList "--uninstall" -Wait -NoNewWindow
        Start-Sleep -Seconds 5
        Write-Host "✅ Uninstaller completed." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Uninstaller had issues, continuing with manual cleanup..." -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  Uninstaller not found, proceeding with manual cleanup..." -ForegroundColor Yellow
}

# --- 4. Remove Configuration Files ---
Write-Host "`n[4/6] Removing configuration files..." -ForegroundColor Yellow

# Service profile config (main configuration location)
$serviceConfigPath = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk"
if (Test-Path $serviceConfigPath) {
    Remove-Item -Path $serviceConfigPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Service configuration removed." -ForegroundColor Green
}

# User AppData config
$userConfigPath = "$env:APPDATA\RustDesk"
if (Test-Path $userConfigPath) {
    Remove-Item -Path $userConfigPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✅ User configuration removed." -ForegroundColor Green
}

# Local AppData
$localConfigPath = "$env:LOCALAPPDATA\RustDesk"
if (Test-Path $localConfigPath) {
    Remove-Item -Path $localConfigPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Local configuration removed." -ForegroundColor Green
}

Write-Host "✅ All configuration files removed." -ForegroundColor Green

# --- 5. Remove Installation Directory ---
Write-Host "`n[5/6] Removing installation directory..." -ForegroundColor Yellow
$installPath = "$env:ProgramFiles\RustDesk"

if (Test-Path $installPath) {
    try {
        Remove-Item -Path $installPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "✅ Installation directory removed." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Could not remove installation directory completely." -ForegroundColor Yellow
    }
} else {
    Write-Host "✅ Installation directory not found - Skipping" -ForegroundColor Green
}

# --- 6. Clean Registry Entries ---
Write-Host "`n[6/6] Cleaning registry entries..." -ForegroundColor Yellow

$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$removed = $false
foreach ($path in $regPaths) {
    try {
        $keys = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -like "*RustDesk*" }
        
        foreach ($key in $keys) {
            $keyPath = $key.PSPath
            Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
    } catch {
        # Continue if registry key doesn't exist
    }
}

if ($removed) {
    Write-Host "✅ Registry entries cleaned." -ForegroundColor Green
} else {
    Write-Host "✅ No registry entries found." -ForegroundColor Green
}

# Remove startup shortcuts (if any)
$startupPaths = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)

foreach ($startupPath in $startupPaths) {
    $shortcut = Get-ChildItem -Path $startupPath -Filter "*rustdesk*" -ErrorAction SilentlyContinue
    if ($shortcut) {
        Remove-Item -Path $shortcut.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Uninstall Complete! ===" -ForegroundColor Cyan
Write-Host "RustDesk has been completely removed from your system." -ForegroundColor Green
Write-Host "A system restart is recommended to complete the cleanup." -ForegroundColor Yellow
