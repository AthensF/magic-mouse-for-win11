#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Apple Magic Mouse scroll (multi-touch) driver on Windows 11.

.DESCRIPTION
    Fixes scroll for Apple Magic Mouse on non-Mac Windows PCs by installing
    Apple's applewirelessmouse.sys as a HID lower filter driver.

    This script:
    1. Detects the Magic Mouse Bluetooth HID device
    2. Copies applewirelessmouse.sys to System32\drivers
    3. Creates the kernel driver service
    4. Registers the driver as a LowerFilter on the device
    5. Restarts the device to activate the driver

.NOTES
    Must be run as Administrator.
    Magic Mouse must be paired and connected via Bluetooth before running.

.LINK
    https://github.com/sbagirici/apple-magic-mouse-scroll-fix-windows
#>

param(
    [switch]$Force,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ── Banner ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   Apple Magic Mouse Scroll Fix for Windows" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Find Magic Mouse ───────────────────────────────────────────────
Write-Host "[1/5] Searching for Magic Mouse..." -ForegroundColor Yellow

# Apple Bluetooth Vendor ID (BT SIG): 0x004C
# Apple USB Vendor ID: 0x05AC
$mouseDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -match "BTHENUM\\\{00001124-0000-1000-8000-00805f9b34fb\}" -and
    $_.InstanceId -match "004C|05AC" -and
    $_.Class -eq "HIDClass"
}

if (-not $mouseDevice) {
    # Broader search — any Bluetooth HID with Apple vendor
    $mouseDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -match "BTHENUM" -and
        $_.InstanceId -match "004C|05AC" -and
        $_.Class -eq "HIDClass"
    }
}

if (-not $mouseDevice) {
    Write-Host ""
    Write-Host "  ERROR: Magic Mouse not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Make sure your Magic Mouse is:" -ForegroundColor Yellow
    Write-Host "    - Paired via Bluetooth Settings" -ForegroundColor Yellow
    Write-Host "    - Connected and showing in Device Manager" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  After pairing, run this script again." -ForegroundColor Yellow
    exit 1
}

# Handle multiple matches (pick the first HID one)
if ($mouseDevice -is [array]) {
    $mouseDevice = $mouseDevice[0]
}

$deviceInstanceId = $mouseDevice.InstanceId
Write-Host "  Found: $($mouseDevice.FriendlyName)" -ForegroundColor Green
Write-Host "  ID:    $deviceInstanceId" -ForegroundColor DarkGray

# ── Step 2: Locate driver file ─────────────────────────────────────────────
Write-Host ""
Write-Host "[2/5] Locating applewirelessmouse.sys..." -ForegroundColor Yellow

$sysDest = "$env:SystemRoot\System32\drivers\applewirelessmouse.sys"
$sysSource = $null

# Check if already installed
if ((Test-Path $sysDest) -and -not $Force) {
    Write-Host "  Already installed at $sysDest" -ForegroundColor Green
    $sysSource = $sysDest
}

if (-not $sysSource -or $Force) {
    # Priority 1: Bundled in repo's driver/ folder
    $bundled = Join-Path $scriptDir "driver\applewirelessmouse.sys"
    if (Test-Path $bundled) {
        $sysSource = $bundled
        Write-Host "  Found bundled driver: $bundled" -ForegroundColor Green
    }

    # Priority 2: Windows DriverStore (from Apple Software Update)
    if (-not $sysSource) {
        $driverStoreFiles = Get-ChildItem -Path "$env:SystemRoot\System32\DriverStore\FileRepository" -Filter "applewirelessmouse.sys" -Recurse -ErrorAction SilentlyContinue
        if ($driverStoreFiles) {
            $sysSource = ($driverStoreFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
            Write-Host "  Found in DriverStore: $sysSource" -ForegroundColor Green
        }
    }

    # Priority 3: Common install locations
    if (-not $sysSource) {
        $searchPaths = @(
            "$env:ProgramFiles\Boot Camp\Drivers\Apple",
            "$env:ProgramFiles (x86)\Boot Camp\Drivers\Apple",
            "$env:ProgramData\Apple\Installer Cache"
        )
        foreach ($searchPath in $searchPaths) {
            if (Test-Path $searchPath) {
                $found = Get-ChildItem -Path $searchPath -Filter "applewirelessmouse.sys" -Recurse -ErrorAction SilentlyContinue
                if ($found) {
                    $sysSource = ($found | Select-Object -First 1).FullName
                    Write-Host "  Found at: $sysSource" -ForegroundColor Green
                    break
                }
            }
        }
    }

    if (-not $sysSource) {
        Write-Host ""
        Write-Host "  ERROR: applewirelessmouse.sys not found!" -ForegroundColor Red
        Write-Host ""
        Write-Host "  To fix this, do ONE of the following:" -ForegroundColor Yellow
        Write-Host "    a) Place applewirelessmouse.sys in the 'driver' subfolder" -ForegroundColor Yellow
        Write-Host "    b) Install Apple Software Update from apple.com/downloads" -ForegroundColor Yellow
        Write-Host "    c) See README.md for manual extraction from Boot Camp" -ForegroundColor Yellow
        exit 1
    }

    # Copy to System32\drivers
    if ($sysSource -ne $sysDest) {
        Write-Host "  Copying to $sysDest..."
        Copy-Item $sysSource $sysDest -Force
        Write-Host "  Copied." -ForegroundColor Green
    }
}

# ── Step 3: Create kernel service ──────────────────────────────────────────
Write-Host ""
Write-Host "[3/5] Creating driver service..." -ForegroundColor Yellow

$svcExists = Get-Service -Name "applewirelessmouse" -ErrorAction SilentlyContinue
if ($svcExists) {
    Write-Host "  Service already exists (Status: $($svcExists.Status))" -ForegroundColor Green
} else {
    $scResult = & sc.exe create applewirelessmouse `
        type= kernel `
        start= demand `
        error= ignore `
        binPath= "System32\drivers\applewirelessmouse.sys" `
        DisplayName= "Apple Wireless Mouse" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Service created." -ForegroundColor Green
    } else {
        Write-Host "  sc.exe output: $scResult" -ForegroundColor Red
        Write-Host "  Failed to create service." -ForegroundColor Red
        exit 1
    }
}

# ── Step 4: Add LowerFilters to device ─────────────────────────────────────
Write-Host ""
Write-Host "[4/5] Registering driver as LowerFilter..." -ForegroundColor Yellow

$deviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceInstanceId"

if (-not (Test-Path $deviceRegPath)) {
    Write-Host "  ERROR: Device registry path not found!" -ForegroundColor Red
    Write-Host "  Path: $deviceRegPath" -ForegroundColor DarkGray
    exit 1
}

$currentFilters = (Get-ItemProperty -Path $deviceRegPath -Name "LowerFilters" -ErrorAction SilentlyContinue).LowerFilters

if ($currentFilters -and ($currentFilters -contains "applewirelessmouse")) {
    Write-Host "  LowerFilter already registered." -ForegroundColor Green
} else {
    if ($currentFilters) {
        $newFilters = @($currentFilters) + @("applewirelessmouse")
    } else {
        $newFilters = @("applewirelessmouse")
    }

    Set-ItemProperty -Path $deviceRegPath -Name "LowerFilters" -Value $newFilters -Type MultiString
    Write-Host "  Added 'applewirelessmouse' to LowerFilters." -ForegroundColor Green
}

# ── Step 5: Restart device ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[5/5] Restarting Bluetooth HID device..." -ForegroundColor Yellow

if ($SkipRestart) {
    Write-Host "  Skipped (use -SkipRestart:$false to enable)." -ForegroundColor DarkGray
} else {
    try {
        Disable-PnpDevice -InstanceId $deviceInstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $deviceInstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Host "  Device restarted." -ForegroundColor Green
    } catch {
        Write-Host "  Could not restart device automatically." -ForegroundColor Yellow
        Write-Host "  Please restart your computer to activate the driver." -ForegroundColor Yellow
    }
}

# ── Result ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   Installation complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""

# Quick verification
$svc = Get-Service -Name "applewirelessmouse" -ErrorAction SilentlyContinue
$sysExists = Test-Path $sysDest
$filters = (Get-ItemProperty -Path $deviceRegPath -Name "LowerFilters" -ErrorAction SilentlyContinue).LowerFilters

Write-Host "  Driver file:    $(if ($sysExists) { 'OK' } else { 'MISSING' })" -ForegroundColor $(if ($sysExists) { 'Green' } else { 'Red' })
Write-Host "  Service:        $(if ($svc) { $svc.Status } else { 'NOT FOUND' })" -ForegroundColor $(if ($svc) { 'Green' } else { 'Red' })
Write-Host "  LowerFilters:   $(if ($filters -contains 'applewirelessmouse') { 'OK' } else { 'MISSING' })" -ForegroundColor $(if ($filters -contains 'applewirelessmouse') { 'Green' } else { 'Red' })
Write-Host ""
Write-Host "  Try scrolling your Magic Mouse now!" -ForegroundColor Cyan
Write-Host "  If it doesn't work, restart your computer." -ForegroundColor Yellow
Write-Host ""
