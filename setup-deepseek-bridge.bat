@echo off
echo ============================================
echo   DeepSeek Reader - Windows Bridge
echo ============================================
echo.

REM Step 1: Kill stuck agent and restart
echo [1/3] Restarting Windows Agent...
powershell -Command "Stop-Process -Id 17524 -Force -ErrorAction SilentlyContinue"
timeout /t 2 /nobreak >nul
start "QDBMS-Agent" /min powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\JetBrains\IntelliJ IDEA 2025.1.3\project\QDBMS\mcp-server\agent.ps1"
echo Agent restarted.

REM Step 2: Start Edge in debug mode
echo [2/3] Starting Edge debug mode...
powershell -ExecutionPolicy Bypass -File "C:\Users\17605\edge-browser\mcp-server\edge-auto-start.ps1"

REM Step 3: Check if we can reach DeepSeek
echo [3/3] Opening DeepSeek in Edge...
start msedge https://chat.deepseek.com/

echo.
echo ============================================
echo   All set! Agent + Edge debug mode running.
echo   DeepSeek opened in Edge.
echo ============================================
echo.
pause
