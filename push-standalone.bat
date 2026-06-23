@echo off
setlocal enabledelayedexpansion
title DeepSeek Reader - Push to GitHub

set "PROJECT_DIR=C:\Users\17605\Desktop\新建文件夹 (2)\deepseek-reader"
cd /d "%PROJECT_DIR%"

echo ============================================
echo   DeepSeek Reader - Auto Push to GitHub
echo ============================================
echo.

:: Step 1: Init repo
echo [1/6] Init git repo...
del /f .git\index.lock 2>nul
if not exist .git (
    git init
    git config user.name "Cowork 3P"
    git config user.email "cowork-3p@localhost"
    git branch -m main
)

:: Step 2: Proxy
echo [2/6] Configure proxy...
git config --global http.proxy http://127.0.0.1:12000
git config --global https.proxy http://127.0.0.1:12000

:: Step 3: Add files
echo [3/6] Add files...
git add README.md SKILL.md LICENSE deepseek_bridge.cjs setup-deepseek-bridge.bat push-standalone.bat 2>nul
git status --short

:: Step 4: Commit (skip if nothing to commit)
echo [4/6] Commit...
git diff --cached --quiet 2>nul
if errorlevel 1 (
    git commit -m "feat: DeepSeek Reader v1.0 - browser automation for DeepSeek conversations"
) else (
    echo Nothing to commit, skipping.
)

:: Step 5: Create GitHub repo via API
echo [5/6] Auto-create GitHub repo...
set "TOKEN="

:: Try gh CLI first
where gh >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%t in ('gh auth token 2^>nul') do set "TOKEN=%%t"
)

:: Fallback: try git credential helper
if "%TOKEN%"=="" (
    echo Trying git credential helper...
    for /f "tokens=2 delims=:" %%a in ('echo host=github.com ^| git credential fill 2^>nul ^| findstr password') do set "TOKEN=%%a"
    set "TOKEN=!TOKEN: =!"
)

:: Create repo
if not "%TOKEN%"=="" (
    echo Creating repo Airay-Johnson/deepseek-reader via API...
    curl -s -X POST https://api.github.com/user/repos ^
        -H "Authorization: token %TOKEN%" ^
        -H "Accept: application/vnd.github.v3+json" ^
        -d "{\"name\":\"deepseek-reader\",\"description\":\"Browser automation tool for reading DeepSeek conversations\",\"private\":false,\"auto_init\":false}" ^
        --proxy http://127.0.0.1:12000 ^
        -o create_result.json 2>&1

    findstr /c:"\"full_name\"" create_result.json >nul 2>&1
    if !errorlevel! equ 0 (
        echo Repo created: Airay-Johnson/deepseek-reader
    ) else (
        findstr /c:"already exists" create_result.json >nul 2>&1
        if !errorlevel! equ 0 (
            echo Repo already exists, continuing...
        ) else (
            echo Repo creation failed - may already exist or token missing.
            type create_result.json 2>nul
        )
    )
    del create_result.json 2>nul
) else (
    echo No GitHub token found. Trying push anyway...
)

:: Step 6: Push
echo [6/6] Push to GitHub...
git -c http.sslBackend=openssl -c http.sslVerify=false -c http.version=HTTP/1.1 remote remove origin 2>nul
git -c http.sslBackend=openssl -c http.sslVerify=false -c http.version=HTTP/1.1 remote add origin https://github.com/Airay-Johnson/deepseek-reader.git 2>nul
git -c http.sslBackend=openssl -c http.sslVerify=false -c http.version=HTTP/1.1 push -u origin main 2>&1

if %errorlevel% neq 0 (
    echo.
    echo HTTPS failed, trying SSH...
    git remote set-url origin git@github.com:Airay-Johnson/deepseek-reader.git
    ssh -T git@github.com 2>&1 | findstr /c:"successfully authenticated" >nul
    if !errorlevel! equ 0 (
        git push -u origin main 2>&1
    ) else (
        echo SSH also failed. Trying HTTPS with direct push...
        git remote set-url origin https://github.com/Airay-Johnson/deepseek-reader.git
        git -c http.sslBackend=openssl -c http.sslVerify=false -c http.version=HTTP/1.1 push --force -u origin main 2>&1
    )
)

echo.
echo ============================================
if %errorlevel% equ 0 (
    echo   SUCCESS! https://github.com/Airay-Johnson/deepseek-reader
) else (
    echo   Push failed. Check errors above.
)
echo ============================================
pause
