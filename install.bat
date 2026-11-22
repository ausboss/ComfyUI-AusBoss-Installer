@echo off
title ComfyUI AusBoss Installer
rem Installs ComfyUI and the AusBoss nodes into a ComfyUI-AusBoss folder next to this file.
rem Put this file somewhere without spaces in the path, for example C:\AI\
cd /d "%~dp0"
if not exist "%~dp0install.ps1" (
    echo Getting install.ps1...
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest 'https://raw.githubusercontent.com/ausboss/ComfyUI-AusBoss-Installer/main/install.ps1' -OutFile '%~dp0install.ps1' -UseBasicParsing"
)
set "DEFAULT_DIR=-Dir "%~dp0ComfyUI-AusBoss""
echo.%* | find /i "-Dir" >nul && set "DEFAULT_DIR="
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %DEFAULT_DIR% %*
pause
