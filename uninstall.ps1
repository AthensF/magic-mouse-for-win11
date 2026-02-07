#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the Apple Magic Mouse scroll driver from Windows.

.DESCRIPTION
    Reverses all changes made by install.ps1:
    1. Removes applewirelessmouse from device LowerFilters
    2. Stops and deletes the kernel driver service
    3. Removes applewirelessmouse.sys from System32\drivers

.NOTES
    Must be run as Administrator.
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   Apple Magic Mouse Driver Uninstaller" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Find device and remove LowerFilters ────────────────────────────
Write-Host "[1/3] Removing LowerFilters from device..." -ForegroundColor Yellow

$mouseDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -match "BTHENUM\\\{00001124-0000-1000-8000-00805f9b34fb\}" -and
    $_.InstanceId -match "004C|05AC" -and
    $_.Class -eq "HIDClass"
}

if ($mouseDevice) {
    if ($mouseDevice -is [array]) { $mouseDevice = $mouseDevice[0] }

    $deviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($mouseDevice.InstanceId)"
    $currentFilters = (Get-ItemProperty -Path $deviceRegPath -Name "LowerFilters" -ErrorAction SilentlyContinue).LowerFilters

    if ($currentFilters -and ($currentFilters -contains "applewirelessmouse")) {
        $newFilters = @($currentFilters | Where-Object { $_ -ne "applewirelessmouse" })
        if ($newFilters.Count -eq 0) {
            Remove-ItemProperty -Path $deviceRegPath -Name "LowerFilters" -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -Path $deviceRegPath -Name "LowerFilters" -Value $newFilters -Type MultiString
        }
        Write-Host "  Removed from LowerFilters." -ForegroundColor Green

        # Restart device
        try {
            Disable-PnpDevice -InstanceId $mouseDevice.InstanceId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 2
            Enable-PnpDevice -InstanceId $mouseDevice.InstanceId -Confirm:$false -ErrorAction Stop
            Write-Host "  Device restarted." -ForegroundColor Green
        } catch {
            Write-Host "  Could not restart device. Restart your computer." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  LowerFilters was already clean." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Magic Mouse not found (may not be connected). Skipping." -ForegroundColor DarkGray
}

# ── Step 2: Remove service ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Removing driver service..." -ForegroundColor Yellow

$svc = Get-Service -Name "applewirelessmouse" -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") {
        & sc.exe stop applewirelessmouse 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }
    & sc.exe delete applewirelessmouse 2>&1 | Out-Null
    Write-Host "  Service removed." -ForegroundColor Green
} else {
    Write-Host "  Service not found (already removed)." -ForegroundColor DarkGray
}

# ── Step 3: Remove driver file ──────────────────────────────────────────────
Write-Host ""
Write-Host "[3/3] Removing driver file..." -ForegroundColor Yellow

$sysDest = "$env:SystemRoot\System32\drivers\applewirelessmouse.sys"
if (Test-Path $sysDest) {
    Remove-Item $sysDest -Force
    Write-Host "  Removed $sysDest" -ForegroundColor Green
} else {
    Write-Host "  Driver file not found (already removed)." -ForegroundColor DarkGray
}

# ── Result ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   Uninstall complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Restart your computer to fully unload the driver." -ForegroundColor Yellow
Write-Host ""
