$ProjectDir = "C:\Users\17605\Desktop\新建文件夹 (2)\deepseek-reader"
Set-Location $ProjectDir
$RepoName = "deepseek-reader"
$RepoUrl = "https://github.com/Airay-Johnson/$RepoName.git"
$ApiUrl = "https://api.github.com/user/repos"

Write-Host "=== DeepSeek Reader - Auto Push to GitHub ===" -ForegroundColor Cyan

# ── Step 1: Init repo ──
Remove-Item -Force "$ProjectDir\.git\index.lock" -ErrorAction SilentlyContinue
if (-not (Test-Path "$ProjectDir\.git")) {
    git init; git config user.name "Cowork 3P"; git config user.email "cowork-3p@localhost"
    git branch -m main
}

# ── Step 2: Commit ──
git add -A
$diff = git diff --cached --quiet 2>&1
if ($LASTEXITCODE -ne 0) { git commit -m "feat: DeepSeek Reader v1.0" }

# ── Step 3: Get GitHub token ──
Write-Host "`n[1] Getting GitHub token..." -ForegroundColor Yellow
$token = $null

# Try 1: gh CLI
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    try { $token = (gh auth token 2>$null).Trim() } catch {}
    if ($token) { Write-Host "  Token from: gh CLI" -ForegroundColor Green }
}

# Try 2: Environment variable
if (-not $token) {
    $token = $env:GITHUB_TOKEN
    if (-not $token) { $token = $env:GH_TOKEN }
    if ($token) { Write-Host "  Token from: env var" -ForegroundColor Green }
}

# Try 3: Git credential helper
if (-not $token) {
    Write-Host "  Trying git credential helper..."
    $credInput = "protocol=https`nhost=github.com`n"
    $credOutput = $credInput | git credential fill 2>$null
    if ($credOutput -match "password=(.+)") {
        $token = $matches[1].Trim()
        Write-Host "  Token from: git credential" -ForegroundColor Green
    }
}

# Try 4: Common token file
if (-not $token) {
    $tokenPaths = @(
        "$env:USERPROFILE\.github\token",
        "$env:USERPROFILE\.config\gh\hosts.yml",
        "$env:USERPROFILE\.git-credentials"
    )
    foreach ($p in $tokenPaths) {
        if (Test-Path $p) {
            $content = Get-Content $p -Raw
            if ($content -match "oauth_token[=:]\s*(\S+)") { $token = $matches[1]; break }
            if ($content -match "token[=:]\s*(\S+)") { $token = $matches[1]; break }
            if ($content -match "https://[^:]+:(\S+)@github") { $token = $matches[1]; break }
            if ($content -match "^gh[op]_\w{36}$") { $token = $content.Trim(); break }
        }
    }
    if ($token) { Write-Host "  Token from: config file" -ForegroundColor Green }
}

# ── Step 4: Create repo via API ──
if ($token) {
    Write-Host "`n[2] Creating GitHub repo '$RepoName'..." -ForegroundColor Yellow

    $body = @{name=$RepoName; description="Browser automation for DeepSeek conversations"; private=$false; auto_init=$false} | ConvertTo-Json
    $headers = @{
        "Authorization" = "token $token"
        "Accept" = "application/vnd.github.v3+json"
        "User-Agent" = "deepseek-reader"
    }

    try {
        $result = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers -Body $body `
            -ContentType "application/json" -Proxy "http://127.0.0.1:12000" -TimeoutSec 15
        Write-Host "  Repo created: $($result.full_name)" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -match "already exists") {
            Write-Host "  Repo already exists, continuing..." -ForegroundColor Yellow
        } elseif ($_.Exception.Message -match "401") {
            Write-Host "  Token invalid. Will try push anyway." -ForegroundColor Red
        } else {
            Write-Host "  API call failed: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "`n[2] No GitHub token found." -ForegroundColor Yellow
    Write-Host "  Create repo manually: https://github.com/new" -ForegroundColor Yellow
    Write-Host "  Or set GITHUB_TOKEN env var and re-run." -ForegroundColor Yellow
}

# ── Step 5: Push ──
Write-Host "`n[3] Pushing to $RepoUrl ..." -ForegroundColor Yellow

git remote remove origin 2>$null
git remote add origin $RepoUrl

git -c http.proxy=http://127.0.0.1:12000 -c https.proxy=http://127.0.0.1:12000 `
    -c http.sslBackend=openssl -c http.sslVerify=false `
    push -u origin main 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
    Write-Host "https://github.com/Airay-Johnson/$RepoName" -ForegroundColor Cyan
} else {
    Write-Host "`nPush failed." -ForegroundColor Red
    if (-not $token) {
        Write-Host "Likely cause: repo doesn't exist and no token to auto-create it."
        Write-Host "Quick fix: create empty repo at https://github.com/new then re-run."
    }
}
Read-Host "`nPress Enter to exit"
