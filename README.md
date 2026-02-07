# Apple Magic Mouse Scroll Fix for Windows 11

Fix scroll (multi-touch gestures) for Apple Magic Mouse on **non-Mac** Windows 11 PCs.

> **Problem:** When you pair a Magic Mouse with a Windows PC via Bluetooth, clicking works but scrolling doesn't. This is because Windows lacks Apple's multi-touch filter driver.

## Quick Start (One-Click Install)

1. Open **PowerShell as Administrator**
2. Run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\install.ps1
```

3. Restart your computer
4. Done — scroll should work!

---

## How It Works

Apple Magic Mouse uses a proprietary multi-touch surface for scrolling. On Mac, macOS handles this natively. On Windows (Boot Camp), Apple provides a **HID lower filter driver** called `applewirelessmouse.sys` that translates multi-touch data into scroll events.

The problem on non-Mac PCs:

| Step | Problem | Solution |
|------|---------|----------|
| 1 | Driver doesn't exist on Windows | Extract from Apple's Boot Camp package |
| 2 | Apple's INF doesn't list Magic Mouse 2's Bluetooth PID (`0323`) | Manually register the driver as a LowerFilter |
| 3 | Boot Camp installer checks for Mac hardware | Skip the installer entirely — install only the driver |

### Architecture

```
┌─────────────────────────────┐
│     Application (Browser)    │
├─────────────────────────────┤
│     Windows HID Stack        │
├─────────────────────────────┤
│  ┌─────────────────────────┐│
│  │ applewirelessmouse.sys  ││  ← LowerFilter (translates multi-touch → scroll)
│  └─────────────────────────┘│
├─────────────────────────────┤
│     Bluetooth HID Driver     │  ← hidbth.sys (built-in)
├─────────────────────────────┤
│     Bluetooth Stack          │
├─────────────────────────────┤
│     Magic Mouse Hardware     │
└─────────────────────────────┘
```

## The PID Mismatch Problem

Apple Magic Mouse reports different Vendor/Product IDs depending on the connection type:

| Connection | Vendor ID | Product ID | Notes |
|-----------|-----------|------------|-------|
| USB (charging) | `VID_05AC` | `PID_0265` | Apple USB Vendor ID |
| Bluetooth (classic) | `VID&000205AC` | `PID&030D` | Magic Mouse 1 |
| Bluetooth (classic) | `VID&000205AC` | `PID&0310` | Magic Mouse 2 (some models) |
| **Bluetooth (BT SIG)** | **`VID&0001004C`** | **`PID&0323`** | **Magic Mouse 2 — most common on Windows** |

Apple's official `applewirelessmouse.inf` only lists `030D`, `0310`, and `0269`. It does **not** include `0323`, which is how most Magic Mouse 2 units identify themselves over Bluetooth on Windows PCs.

This installer bypasses the INF matching entirely by:
1. Copying the `.sys` file directly
2. Creating the kernel service manually
3. Adding the driver as a `LowerFilters` entry on the specific device

## What the Installer Does

The `install.ps1` script performs these steps:

1. **Detects** the Magic Mouse Bluetooth HID device by scanning for Apple's Bluetooth Vendor ID (`004C`)
2. **Locates** `applewirelessmouse.sys` — checks DriverStore first (from Apple Software Update), then extracts from bundled copy
3. **Copies** the driver to `%SystemRoot%\System32\drivers\`
4. **Creates** a kernel driver service (`applewirelessmouse`)
5. **Adds** `applewirelessmouse` to the device's `LowerFilters` registry key
6. **Restarts** the Bluetooth HID device to load the filter

### What It Does NOT Do

- Does not install the full Boot Camp package
- Does not modify system boot configuration
- Does not require Secure Boot to be disabled
- Does not install any Apple background services
- Does not affect other Bluetooth devices

## Uninstall

Run as Administrator:

```powershell
.\uninstall.ps1
```

Or manually:

```powershell
# Remove LowerFilters from device
# (find your device's InstanceId first with Get-PnpDevice)
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\<YOUR_DEVICE_INSTANCE_ID>"
Remove-ItemProperty -Path $regPath -Name "LowerFilters"

# Remove service
sc.exe delete applewirelessmouse

# Remove driver file
Remove-Item "$env:SystemRoot\System32\drivers\applewirelessmouse.sys"
```

## Compatibility

| Item | Status |
|------|--------|
| Windows 11 (23H2, 24H2) | Tested |
| Windows 10 (21H2+) | Should work |
| Magic Mouse 2 (A1657) | Tested |
| Magic Mouse 1 (A1296) | Should work |
| Secure Boot | Compatible (driver is Microsoft-signed) |
| ARM64 (Snapdragon) | Not tested |

## Troubleshooting

### Scroll still doesn't work after install
1. Restart your computer
2. Unpair the Magic Mouse from Bluetooth settings, then pair again
3. Run `install.ps1` again after re-pairing (device InstanceId may change)

### Device not found during install
- Make sure Magic Mouse is paired and connected via Bluetooth
- Check that it appears in Device Manager under "Bluetooth" or "Human Interface Devices"

### "Access Denied" errors
- You must run PowerShell **as Administrator**

### Driver loads but scroll is laggy/inverted
- This is the expected Apple scroll behavior — it matches Mac trackpad direction
- Use [Mac Mouse Fix](https://macmousefix.com/) alternatives or registry tweaks to adjust

## File Structure

```
apple-magic-mouse-windows/
├── install.ps1              # One-click installer (run as admin)
├── uninstall.ps1            # Clean uninstaller
├── driver/
│   └── applewirelessmouse.sys   # Apple's signed driver (from Boot Camp 6)
├── README.md                # This file
└── LICENSE                  # MIT License
```

## Driver Source

The `driver/applewirelessmouse.sys` file is Apple's official Boot Camp driver, extracted from Apple's publicly available Boot Camp Support Software. It is digitally signed by Apple and countersigned by Microsoft (WHQL).

If you want to extract it yourself:

1. **Apple Software Update for Windows** — Install from [Apple's website](https://support.apple.com/downloads), the driver will appear in `C:\Windows\System32\DriverStore\FileRepository\applewirelessmouse.inf_amd64_*\`

2. **Boot Camp Support Software** — Download via [Brigadier](https://github.com/timsutton/brigadier), then extract `AppleWirelessMouse64.exe` with 7-Zip

3. **BootCampESD.pkg** — Download from Apple's software update catalog, extract with 7-Zip:
   ```
   BootCampESD.pkg → (xar) → Payload → (cpio) → WindowsSupport.dmg → (dmg/iso)
   → BootCamp/Drivers/Apple/AppleWirelessMouse64.exe → (rar) → applewirelessmouse.sys
   ```

## Credits

- Apple Inc. — `applewirelessmouse.sys` driver
- [Brigadier](https://github.com/timsutton/brigadier) — Boot Camp driver download tool

## License

MIT License — see [LICENSE](LICENSE). Note: `applewirelessmouse.sys` is Apple's proprietary driver and subject to Apple's software license terms.
