@echo off
echo ============================================
echo   DeepSeek Reader - Setup
echo ============================================
echo.

:: Get script directory (portable)
set "SCRIPT_DIR=%~dp0"

echo [1/3] Starting Windows Agent...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_DIR%agent.ps1"
echo Agent started.

echo [2/3] Starting Edge debug mode...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%edge-auto-start.ps1"

echo [3/3] Opening DeepSeek...
start msedge https://chat.deepseek.com/

echo.
echo ============================================
echo   Done! Agent + Edge CDP running.
echo   Login to DeepSeek, then use:
echo     node deepseek_bridge.cjs list
echo ============================================
pause
