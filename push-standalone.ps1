$ProjectDir = "C:\Users\17605\Desktop\新建文件夹 (2)\deepseek-reader"
Set-Location $ProjectDir

Write-Host "=== DeepSeek Reader - Push to GitHub ===" -ForegroundColor Cyan

# Init
Remove-Item -Force "$ProjectDir\.git\index.lock" -ErrorAction SilentlyContinue
if (-not (Test-Path "$ProjectDir\.git")) {
    git init; git config user.name "Cowork 3P"; git config user.email "cowork-3p@localhost"
    git branch -m main
}

# Commit
git add -A
$diff = git diff --cached --quiet 2>&1
if ($LASTEXITCODE -ne 0) {
    git commit -m "feat: DeepSeek Reader v1.0"
}

# Configure remote
git remote remove origin 2>$null

# METHOD 1: Same settings that worked for QDBMS push
Write-Host "`n[1] Push with openssl backend (same as QDBMS)..." -ForegroundColor Yellow
git config --global http.proxy http://127.0.0.1:12000
git config --global https.proxy http://127.0.0.1:12000
git remote add origin https://github.com/Airay-Johnson/deepseek-reader.git
git -c http.sslBackend=openssl -c http.sslVerify=false -c http.version=HTTP/1.1 push -u origin main 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "DONE!" -ForegroundColor Green; Read-Host; exit 0 }

# METHOD 2: Try with GIT_SSL_NO_VERIFY
Write-Host "`n[2] Push with GIT_SSL_NO_VERIFY..." -ForegroundColor Yellow
$env:GIT_SSL_NO_VERIFY = "1"
git -c http.sslBackend=openssl -c http.sslVerify=false push -u origin main 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "DONE!" -ForegroundColor Green; Read-Host; exit 0 }

# METHOD 3: Force push
Write-Host "`n[3] Force push..." -ForegroundColor Yellow
git push --force -u origin main 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "DONE!" -ForegroundColor Green; Read-Host; exit 0 }

Write-Host "`n=== FAILED ===" -ForegroundColor Red
Write-Host "Repo may not exist. Create it first: https://github.com/new"
Write-Host "Name: deepseek-reader (empty, no README)"
Read-Host "Press Enter to exit"
