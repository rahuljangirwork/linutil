# ==============================================================================
# RustDesk Silent Install & Configuration (Rerunnable) - FIXED
# ==============================================================================

$ErrorActionPreference = "Stop"
Write-Host "`n=== RustDesk Setup ===" -ForegroundColor Cyan

$rustDeskPath = "$env:ProgramFiles\RustDesk\rustdesk.exe"
$installerPath = "$env:TEMP\rustdesk-installer.exe"
$url = "https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-x86_64.exe"

# --- Check if RustDesk is Already Installed ---
function Test-RustDeskInstalled {
    if (Test-Path $rustDeskPath) {
        return $true
    }
    
    # Check registry for installation
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $regPaths) {
        $installed = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                     Where-Object { $_.DisplayName -like "*RustDesk*" }
        if ($installed) { return $true }
    }
    
    return $false
}

# --- 1. Download RustDesk ---
if (Test-RustDeskInstalled) {
    Write-Host "[1/5] RustDesk already installed - Skipping download" -ForegroundColor Green
} else {
    Write-Host "[1/5] Downloading RustDesk..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing
        Write-Host "✅ Download complete." -ForegroundColor Green
    } catch {
        Write-Host "❌ Download failed." -ForegroundColor Red
        exit 1
    }
}

# --- 2. Silent Installation ---
if (Test-RustDeskInstalled) {
    Write-Host "[2/5] RustDesk already installed - Skipping installation" -ForegroundColor Green
} else {
    Write-Host "[2/5] Installing RustDesk (Silent)..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath $installerPath -ArgumentList "--silent-install" -Wait -NoNewWindow
        Start-Sleep -seconds 15
        Write-Host "✅ Installation complete." -ForegroundColor Green
    } catch {
        Write-Host "❌ Installation failed." -ForegroundColor Red
        exit 1
    }
}

# --- 3. Ensure Service is Running ---
Write-Host "`n[3/5] Checking RustDesk Service..." -ForegroundColor Yellow

if (-not (Test-Path $rustDeskPath)) {
    Write-Host "❌ RustDesk executable not found" -ForegroundColor Red
    exit 1
}

$ServiceName = 'Rustdesk'
$arrService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($arrService -eq $null) {
    Write-Host "Installing service..." -ForegroundColor Yellow
    cd "$env:ProgramFiles\RustDesk"
    # FIXED: Use -ArgumentList properly
    Start-Process .\rustdesk.exe -ArgumentList "--install-service" -Wait -NoNewWindow
    Start-Sleep -seconds 10
    $arrService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
}

if ($arrService -ne $null) {
    if ($arrService.Status -eq 'Running') {
        Write-Host "✅ Service already running - Skipping" -ForegroundColor Green
    } else {
        Write-Host "Starting service..." -ForegroundColor Yellow
        Start-Service $ServiceName
        Start-Sleep -seconds 5
        Write-Host "✅ Service started." -ForegroundColor Green
    }
} else {
    Write-Host "⚠️  Service not found, but continuing..." -ForegroundColor Yellow
}

# --- 4. Apply Configuration ---
Write-Host "`n[4/5] Applying Configuration..." -ForegroundColor Yellow
cd "$env:ProgramFiles\RustDesk"

$configString = "==Qfi0TV2EmeqxkTkdzcuVXRjdVO080VYNmWHhWMUJnc0sGUWtGb1pWU5UkeFhUTiojI5V2aiwiI0ETMxIjOwETMuMjMx4yM44CMwEzLvoDc0RHaiojIpBXYiwiI3ETMxIjOwETMuMjMx4yM44CMwEjI6ISehxWZyJCLiYTMxEjM6ATMx4yMyEjLzgjLwATMiojI0N3boJye"
$password = "Gms@8087"

try {
    & .\rustdesk.exe --config $configString
    Write-Host "✅ Network configuration applied." -ForegroundColor Green
    
    & .\rustdesk.exe --password $password
    Write-Host "✅ Permanent password set." -ForegroundColor Green
    
    & .\rustdesk.exe --option hide-tray=Y
    Write-Host "✅ Tray icon hidden." -ForegroundColor Green
} catch {
    Write-Host "⚠️  Configuration partially applied." -ForegroundColor Yellow
}

# --- 5. Cleanup ---
if (Test-Path $installerPath) {
    Remove-Item $installerPath -Force
    Write-Host "`n[5/5] Cleanup complete." -ForegroundColor Green
}

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Cyan
Write-Host "RustDesk is ready. Script is rerunnable - completed steps will be skipped." -ForegroundColor Green
