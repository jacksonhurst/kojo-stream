@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-transcode-proxy.ps1" %*

if errorlevel 1 (
    echo.
    pause
)
