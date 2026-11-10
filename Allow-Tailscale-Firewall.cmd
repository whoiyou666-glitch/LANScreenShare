@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Allow-Tailscale-Firewall.ps1"
echo.
echo Press any key to close...
pause >nul
