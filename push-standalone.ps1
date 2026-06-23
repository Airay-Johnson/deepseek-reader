$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir
$RepoName = "deepseek-reader"
$RepoUrl = "https://github.com/Airay-Johnson/$RepoName.git"
$ApiUrl = "https://api.github.com/user/repos"
$ProxyUrl = "http://127.0.0.1:12000"

Write-Host "=== DeepSeek Reader - Auto Push to GitHub ===" -ForegroundColor Cyan
Write-Host "Dir: $ProjectDir"
Write-Host ""

# ── Step 1: Init repo ──
Remove-Item -Force "$ProjectDir\.git\index.lock" -ErrorAction SilentlyContinue
if (-not (Test-Path "$ProjectDir\.git")) {
    git init
    git config user.name "Cowork 3P"
    git config user.email "cowork-3p@localhost"
    git branch -m main
} else {
    git config user.name "Cowork 3P"
    git config user.email "cowork-3p@localhost"
}

# ── Step 2: Commit ──
git add -A
$diff = git diff --cached --quiet 2>&1
if ($LASTEXITCODE -ne 0) {
    git commit -m "feat: DeepSeek Reader v1.0"
    Write-Host "Committed." -ForegroundColor Green
} else {
    Write-Host "Nothing to commit." -ForegroundColor Yellow
}

# ── Step 3: Get GitHub token ──
Write-Host "`nSearching for GitHub token..." -ForegroundColor Yellow
$token = $null

# Try 1: gh CLI
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    try { $token = (gh auth token 2>$null).Trim() } catch {}
    if ($token) { Write-Host "  Found: gh CLI" -ForegroundColor Green }
}

# Try 2: env vars
if (-not $token) {
    if ($env:GITHUB_TOKEN) { $token = $env:GITHUB_TOKEN.Trim() }
    elseif ($env:GH_TOKEN) { $token = $env:GH_TOKEN.Trim() }
    if ($token) { Write-Host "  Found: env var" -ForegroundColor Green }
}

# Try 3: git credential helper - safe parsing
if (-not $token) {
    try {
        $credOut = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
        $lines = $credOut -split "`n"
        foreach ($line in $lines) {
            if ($line -match "^password=(.+)$") {
                $token = $matches[1].Trim()
                break
            }
        }
        if ($token) { Write-Host "  Found: git credential" -ForegroundColor Green }
    } catch {}
}

# Try 4: Common config files
if (-not $token) {
    $paths = @(
        "$env:USERPROFILE\.config\gh\hosts.yml",
        "$env:USERPROFILE\.git-credentials"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $c = Get-Content $p -Raw -ErrorAction SilentlyContinue
            if ($c -match "oauth_token[=:]\s*(\S+)") { $token = $matches[1]; break }
            if ($c -match "https://[^:]+:(\S+)@github") { $token = $matches[1]; break }
            # gh hosts.yml format
            if ($c -match "oauth_token:\s*(\S+)") { $token = $matches[1]; break }
        }
    }
    if ($token) { Write-Host "  Found: config file" -ForegroundColor Green }
}

if (-not $token) {
    Write-Host "  No token found." -ForegroundColor Red
}

# ── Step 4: Create repo via API ──
if ($token) {
    Write-Host "`nCreating GitHub repo '$RepoName'..." -ForegroundColor Yellow

    $body = @{
        name = $RepoName
        description = "Browser automation for DeepSeek conversations"
        private = $false
        auto_init = $false
    } | ConvertTo-Json -Compress

    try {
        $result = Invoke-RestMethod -Uri $ApiUrl -Method Post `
            -Headers @{
                "Authorization" = "token $token"
                "Accept" = "application/vnd.github.v3+json"
                "User-Agent" = "deepseek-reader"
            } `
            -Body $body -ContentType "application/json" `
            -Proxy $ProxyUrl -TimeoutSec 15

        Write-Host "  Repo created: $($result.html_url)" -ForegroundColor Green
    } catch {
        $err = $_.Exception.Message
        if ($err -match "already exists" -or $err -match "422") {
            Write-Host "  Repo already exists." -ForegroundColor Yellow
        } elseif ($err -match "401" -or $err -match "Bad credentials") {
            Write-Host "  Token invalid." -ForegroundColor Red
            $token = $null
        } else {
            Write-Host "  API error: $err" -ForegroundColor Red
        }
    }
}

if (-not $token) {
    Write-Host "`nManual step needed:" -ForegroundColor Yellow
    Write-Host "  1. Open https://github.com/new" -ForegroundColor White
    Write-Host "  2. Name: deepseek-reader (empty, no README)" -ForegroundColor White
    Write-Host "  3. Click Create, then press Enter here..." -ForegroundColor White
    Read-Host
}

# ── Step 5: Push ──
Write-Host "`nPushing to $RepoUrl ..." -ForegroundColor Yellow

git remote remove origin 2>$null
git remote add origin $RepoUrl

$pushResult = git -c http.proxy=$ProxyUrl -c https.proxy=$ProxyUrl `
    -c http.sslBackend=openssl -c http.sslVerify=false `
    push -u origin main 2>&1
$exitCode = $LASTEXITCODE

Write-Host $pushResult

if ($exitCode -eq 0) {
    Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
    Write-Host "https://github.com/Airay-Johnson/$RepoName" -ForegroundColor Cyan
} else {
    Write-Host "`nPush failed. Error above." -ForegroundColor Red
}

Read-Host "`nPress Enter to exit"
