@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ScreenShare.ps1"
echo.
echo Press any key to close...
pause >nul
