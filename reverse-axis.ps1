#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reverses (flips) the scroll axis on an Apple Magic Mouse on Windows 11.

.DESCRIPTION
    Sets FlipFlopWheel and FlipFlopHScroll to 1 on the Magic Mouse's
    HID-compliant mouse device, so scrolling behaves like macOS "natural"
    scrolling. Auto-detects the device by Apple's Bluetooth vendor ID.

    To revert to default Windows direction, set $FlipBack = $true below
    (or pass -FlipBack) and re-run.

.NOTES
    Must be run as Administrator.
    Magic Mouse must be paired and connected via Bluetooth before running.
#>

param(
    [switch]$FlipBack
)

$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'reverse-axis.log'
"=== Reverse axis script started $(Get-Date) ===" | Out-File $log

$value = if ($FlipBack) { 0 } else { 1 }
$label = if ($FlipBack) { 'default (0)' } else { 'reversed (1)' }
"Target value: $label" | Out-File $log -Append

# Find the Magic Mouse's HID-compliant mouse device.
# Apple Bluetooth vendor ID appears as 0001004C (BT SIG) or 000205AC (classic).
$mouse = Get-PnpDevice -Class Mouse -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -match '0001004C|000205AC|05AC'
}

if (-not $mouse) {
    "ERROR: No Apple Magic Mouse HID-compliant mouse device found." | Out-File $log -Append
    "Make sure the Magic Mouse is paired and connected, then re-run." | Out-File $log -Append
    Write-Host "ERROR: Magic Mouse not found. See log: $log" -ForegroundColor Red
    exit 1
}

if ($mouse -is [array]) { $mouse = $mouse[0] }
$dev = $mouse.InstanceId
"Device: $dev" | Out-File $log -Append
Write-Host "Found: $($mouse.FriendlyName)" -ForegroundColor Green
Write-Host "ID:    $dev" -ForegroundColor DarkGray

$paramsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$dev\Device Parameters"
"Params path: $paramsPath" | Out-File $log -Append

try {
    Set-ItemProperty -Path $paramsPath -Name FlipFlopWheel -Value $value -Type DWord
    "Set FlipFlopWheel = $value" | Out-File $log -Append
    Set-ItemProperty -Path $paramsPath -Name FlipFlopHScroll -Value $value -Type DWord
    "Set FlipFlopHScroll = $value" | Out-File $log -Append

    $result = Get-ItemProperty $paramsPath | Select-Object FlipFlopWheel, FlipFlopHScroll
    "Result: FlipFlopWheel=$($result.FlipFlopWheel) FlipFlopHScroll=$($result.FlipFlopHScroll)" | Out-File $log -Append
    Write-Host "FlipFlopWheel=$($result.FlipFlopWheel) FlipFlopHScroll=$($result.FlipFlopHScroll)" -ForegroundColor Green

    # NOTE: We intentionally do NOT restart the device here.
    # Restarting the HID mouse device can cause the parent Bluetooth HID
    # device to re-enumerate, which clears the LowerFilters registry key
    # and detaches Apple's applewirelessmouse scroll driver. The FlipFlop
    # values apply on the next device power cycle or reboot instead.
    "Device restart skipped to avoid dropping the scroll driver filter." | Out-File $log -Append
    Write-Host ""
    Write-Host "Registry updated. To apply the change, do ONE of the following:" -ForegroundColor Cyan
    Write-Host "  - Toggle Bluetooth off/on for the Magic Mouse, or" -ForegroundColor Cyan
    Write-Host "  - Reconnect the mouse, or" -ForegroundColor Cyan
    Write-Host "  - Reboot your computer" -ForegroundColor Cyan
} catch {
    "ERROR: $_" | Out-File $log -Append
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

"=== Done $(Get-Date) ===" | Out-File $log -Append
