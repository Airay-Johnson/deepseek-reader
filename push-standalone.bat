@echo off
setlocal

set PROJECT_DIR=C:\Users\17605\Desktop\????? (2)\deepseek-reader
cd /d "%PROJECT_DIR%"

echo === DeepSeek Reader - Push to GitHub ===
echo.

echo [1/6] Init git repo...
del /f .git\index.lock 2>nul
if not exist .git (
    git init
    git config user.name "Cowork 3P"
    git config user.email "cowork-3p@localhost"
    git branch -m main
)

echo [2/6] Add and commit...
git add -A
git diff --cached --quiet 2>nul
if errorlevel 1 (
    git commit -m "feat: DeepSeek Reader v1.0"
) else (
    echo Nothing to commit.
)

echo [3/6] Test proxy...
curl -s -x http://127.0.0.1:12000 https://github.com -o nul -w "PROXY_HTTP_CODE:%%{http_code}" --connect-timeout 10 2>&1
echo.

echo [4/6] Try push via proxy...
git -c http.proxy=http://127.0.0.1:12000 -c https.proxy=http://127.0.0.1:12000 -c http.sslVerify=false -c http.sslBackend=schannel push -u origin https://github.com/Airay-Johnson/deepseek-reader.git main 2>&1
if %errorlevel% equ 0 goto DONE

echo [5/6] Try push DIRECT (no proxy)...
git -c http.proxy= -c https.proxy= push -u origin https://github.com/Airay-Johnson/deepseek-reader.git main 2>&1
if %errorlevel% equ 0 goto DONE

echo [6/6] Try SSH...
git -c http.proxy= -c https.proxy= remote set-url origin git@github.com:Airay-Johnson/deepseek-reader.git 2>nul
ssh -o ConnectTimeout=10 -T git@github.com 2>&1 | findstr "success" >nul
if %errorlevel% equ 0 (
    git push -u origin main 2>&1
    if %errorlevel% equ 0 goto DONE
)

echo.
echo === ALL METHODS FAILED ===
echo Proxy SSL issue. Need to fix Clash or use different proxy.
pause
exit /b 1

:DONE
echo.
echo === SUCCESS ===
echo https://github.com/Airay-Johnson/deepseek-reader
pause
