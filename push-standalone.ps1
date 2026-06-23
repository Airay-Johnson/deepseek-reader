$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir
$RepoName = "deepseek-reader"
$RepoUrl = "https://github.com/Airay-Johnson/$RepoName.git"
$ApiUrl = "https://api.github.com/user/repos"
$ProxyUrl = "http://127.0.0.1:12000"

Write-Host "=== DeepSeek Reader - Push to GitHub ===" -ForegroundColor Cyan
Write-Host "Dir: $ProjectDir`n"

# ── Init & Commit ──
Remove-Item -Force "$ProjectDir\.git\index.lock" -ErrorAction SilentlyContinue
if (-not (Test-Path "$ProjectDir\.git")) {
    git init; git config user.name "Cowork 3P"; git config user.email "cowork-3p@localhost"
    git branch -m main
}
git add -A
git diff --cached --quiet 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { git commit -m "feat: DeepSeek Reader v1.0" }

# ── Get token ──
$token = $null
if ($env:GITHUB_TOKEN) { $token = $env:GITHUB_TOKEN.Trim() }
elseif ($env:GH_TOKEN) { $token = $env:GH_TOKEN.Trim() }
if (-not $token) {
    $credOut = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
    foreach ($line in ($credOut -split "`n")) {
        if ($line -match "^password=(.+)$") { $token = $matches[1].Trim(); break }
    }
}

# ── Create repo ──
if ($token) {
    Write-Host "Creating repo..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post `
            -Headers @{Authorization="token $token"; Accept="application/vnd.github.v3+json"; "User-Agent"="deepseek-reader"} `
            -Body (@{name=$RepoName; private=$false; auto_init=$false} | ConvertTo-Json -Compress) `
            -ContentType "application/json" -Proxy $ProxyUrl -TimeoutSec 15 | Out-Null
        Write-Host "  Repo ready: $RepoUrl" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -match "already exists|422") { Write-Host "  Repo exists." -ForegroundColor Yellow }
        else { Write-Host "  API error: $_" -ForegroundColor Red }
    }
}

# ── Set remote ──
git remote remove origin 2>$null
git remote add origin $RepoUrl

# ── Try multiple push methods ──
$methods = @(
    @{Label="schannel + global proxy config"; Cmd={
        git config --global http.proxy $ProxyUrl
        git config --global https.proxy $ProxyUrl
        git -c http.sslBackend=schannel -c http.sslVerify=false push -u origin main 2>&1
    }},
    @{Label="openssl + HTTP/1.1"; Cmd={
        git -c http.proxy=$ProxyUrl -c https.proxy=$ProxyUrl -c http.sslBackend=openssl -c http.sslVerify=false -c http.version=HTTP/1.1 push -u origin main 2>&1
    }},
    @{Label="openssl + force"; Cmd={
        git -c http.proxy=$ProxyUrl -c https.proxy=$ProxyUrl -c http.sslBackend=openssl -c http.sslVerify=false push --force -u origin main 2>&1
    }},
    @{Label="no compression"; Cmd={
        git -c http.proxy=$ProxyUrl -c https.proxy=$ProxyUrl -c http.sslBackend=schannel -c http.sslVerify=false -c core.compression=0 -c http.postBuffer=524288000 push -u origin main 2>&1
    }}
)

foreach ($m in $methods) {
    Write-Host "`nTrying: $($m.Label)..." -ForegroundColor Yellow
    $result = & $m.Cmd
    Write-Host $result
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
        Write-Host "https://github.com/Airay-Johnson/$RepoName" -ForegroundColor Cyan
        Read-Host "`nPress Enter to exit"
        exit 0
    }
}

Write-Host "`nAll methods failed." -ForegroundColor Red
Read-Host "`nPress Enter to exit"
