<#
  Edge 自动调试模式启动器
  用法: 双击运行此脚本，或: powershell -ExecutionPolicy Bypass -File edge-auto-start.ps1
  
  功能:
  1. 如果 Edge 已在调试模式运行 → 什么都不做，直接可用
  2. 如果 Edge 在普通模式运行 → 自动关闭并以调试模式重启
  3. 如果 Edge 未运行 → 直接以调试模式启动
#>

$debugPort = 9222

# 尝试连接已有的调试端口
try {
    $response = Invoke-WebRequest -Uri "http://localhost:$debugPort/json" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    $tabs = $response.Content | ConvertFrom-Json
    $pageCount = ($tabs | Where-Object { $_.type -eq 'page' }).Count
    Write-Host "✅ Edge 调试模式已在运行 (端口 $debugPort, $pageCount 个标签页)" -ForegroundColor Green
    Write-Host "   无需任何操作，直接在 Cowork 中使用即可" -ForegroundColor Gray
    exit 0
} catch {
    Write-Host "Edge 调试模式未运行，正在自动配置..." -ForegroundColor Yellow
}

# 找到 Edge 路径
$edgePaths = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:LOCALAPPDATA}\Microsoft\Edge\Application\msedge.exe"
)
$edgePath = $null
foreach ($p in $edgePaths) {
    if (Test-Path $p) { $edgePath = $p; break }
}
if (-not $edgePath) {
    Write-Host "❌ 找不到 Edge 安装路径" -ForegroundColor Red
    exit 1
}

# 关闭现有 Edge 进程（会丢失当前打开的标签页，所以先提示）
$existing = Get-Process msedge -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "正在关闭现有 Edge (标签页会在调试模式中恢复)..." -ForegroundColor Yellow
    Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# 启动调试模式
$debugDir = "$env:USERPROFILE\EdgeDebug"
New-Item -ItemType Directory -Path $debugDir -Force | Out-Null

Write-Host "正在启动 Edge 调试模式..." -ForegroundColor Cyan
Start-Process -FilePath $edgePath -ArgumentList @(
    "--remote-debugging-port=$debugPort",
    "--user-data-dir=`"$debugDir`"",
    "--restore-last-session"   # 恢复上次的标签页
)

Start-Sleep -Seconds 3

# 验证
try {
    $response = Invoke-WebRequest -Uri "http://localhost:$debugPort/json" -UseBasicParsing -TimeoutSec 5
    Write-Host "✅ 成功！Edge 调试模式已启动 (端口 $debugPort)" -ForegroundColor Green
    Write-Host "   现在可以在 Cowork 中使用了" -ForegroundColor Gray
} catch {
    Write-Host "⚠ 启动后验证失败，请手动检查 Edge 是否已打开" -ForegroundColor Yellow
    Write-Host "   如果 Edge 没打开，手动运行: & `"$edgePath`" --remote-debugging-port=$debugPort --user-data-dir=`"$debugDir`"" -ForegroundColor Gray
}
