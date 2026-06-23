@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0push-standalone.ps1"
pause
