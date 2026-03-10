# GlazeWM + Zebar Configuration Backup

Backup created: 2026-03-03

## Directory Structure

```
glzr-vXXX/
├── glazewm/
│   └── config.yaml          # GlazeWM window manager config
└── zebar/
    └── vanilla-clear/       # Custom status bar widget
        ├── vanilla-clear.html   # Main widget (React)
        ├── styles.css           # Widget styles
        ├── zpack.json           # Zebar widget pack config
        ├── flash-monitor.ps1    # Background script for notification detection
        └── start-flash-monitor.vbs  # Hidden launcher for flash monitor
```

## Features

### Network Display
- Shows active connection (Ethernet/Wi-Fi with SSID)
- VPN detection (ProtonVPN) with shield icon
- Bypasses VPN to show underlying connection

### Notification Indicator
- Yellow dot appears when any app flashes in taskbar
- Configurable app exclusions in `flash-monitor.ps1`
- Extensible for per-app colors in `APP_COLORS` object

## Restore Instructions

```powershell
# Copy configs back to Windows
backup_path="/home/jose/repos/configs/windows/glzr_v001"
glzr_target="/mnt/c/Users/Jose/.glzr"
cp -r $backup_path/* $glzr_target/glazewm/
cp -r $backup_path/zebar/vanilla-clear/* $glzr_target/zebar/vanilla-clear/

# Create runtime state file
echo '{"hasNotifications":false,"apps":[],"count":0}' > $glzr_target/zebar/vanilla-clear/flash-state.json
```

Then reload GlazeWM with `Alt+Shift+R`.
