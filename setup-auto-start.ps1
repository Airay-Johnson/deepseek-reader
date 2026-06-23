# Windows Agent 一键配置 — 开机自启 + 立即启动
# 运行一次，以后永久自动

$ErrorActionPreference = "Stop"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Windows Agent 自动启动配置" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$agentDir = "D:\JetBrains\IntelliJ IDEA 2025.1.3\project\QDBMS\mcp-server"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "QDBMS-Agent.lnk"
$vbsPath = Join-Path $agentDir "start-agent-hidden.vbs"

# 1. 检查 Python
Write-Host "[1/4] 检查 Python..." -ForegroundColor Yellow
try {
    $pyVersion = python --version 2>&1
    Write-Host "  OK: $pyVersion" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: 未找到 Python，请先安装 Python 3.8+" -ForegroundColor Red
    Write-Host "  下载: https://www.python.org/downloads/" -ForegroundColor Red
    pause
    exit 1
}

# 2. 安装截图依赖
Write-Host "[2/4] 安装截图依赖..." -ForegroundColor Yellow
python -c "from PIL import Image; import mss" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  安装 Pillow + mss..." -ForegroundColor Yellow
    pip install Pillow mss --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: 截图库安装失败，截图功能将不可用" -ForegroundColor Yellow
    } else {
        Write-Host "  OK: 截图库已安装" -ForegroundColor Green
    }
} else {
    Write-Host "  OK: 截图库已就绪" -ForegroundColor Green
}

# 3. 创建隐藏启动 VBS（后台运行，无 CMD 窗口）
Write-Host "[3/4] 创建后台启动脚本..." -ForegroundColor Yellow
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "$agentDir"
WshShell.Run "pythonw.exe windows-agent.py", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII
Write-Host "  OK: $vbsPath" -ForegroundColor Green

# 4. 创建开机启动快捷方式
Write-Host "[4/4] 创建开机自启快捷方式..." -ForegroundColor Yellow
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = "wscript.exe"
$Shortcut.Arguments = "`"$vbsPath`""
$Shortcut.WorkingDirectory = $agentDir
$Shortcut.WindowStyle = 7  # 最小化
$Shortcut.Description = "QDBMS Windows Agent — Claude 桌面桥接"
$Shortcut.Save()
Write-Host "  OK: $shortcutPath" -ForegroundColor Green

# 5. 立即启动 Agent（本次生效）
Write-Host ""
Write-Host "启动 Agent..." -ForegroundColor Cyan
wscript.exe "`"$vbsPath`""
Start-Sleep -Seconds 2

# 验证启动
$heartbeatFile = Join-Path $agentDir "..\..\..\..\..\..\..\..\..\..\..\..\..\..\..\..\..\..\..\..\Local\Claude-3p\local-agent-mode-sessions\d30e8174-dd36-4078-b9d6-cfda8ebf810d\00000000-0000-4000-8000-000000000001\local_99a99ec4-5ca6-4864-8815-6a34c99be56b\outputs\edge-browser\mcp-server\sys-heartbeat.json"
# 简化路径 — 直接用 outputs 目录
$outputsDir = "$env:LOCALAPPDATA\Claude-3p\local-agent-mode-sessions\d30e8174-dd36-4078-b9d6-cfda8ebf810d\00000000-0000-4000-8000-000000000001\local_99a99ec4-5ca6-4864-8815-6a34c99be56b\outputs\edge-browser\mcp-server"
$heartbeatFile = Join-Path $outputsDir "sys-heartbeat.json"

# 等待 agent 写心跳
Write-Host "等待 Agent 就绪..." -ForegroundColor Yellow
$ready = $false
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $heartbeatFile) {
        try {
            $hb = Get-Content $heartbeatFile -Raw | ConvertFrom-Json
            if ($hb.status -eq "alive") {
                Write-Host ""
                Write-Host "========================================" -ForegroundColor Green
                Write-Host "  Agent 已启动并运行中！" -ForegroundColor Green
                Write-Host "  PID: $($hb.pid)" -ForegroundColor Green
                Write-Host "  下次开机自动启动，无需手动操作" -ForegroundColor Green
                Write-Host "========================================" -ForegroundColor Green
                $ready = $true
                break
            }
        } catch {}
    }
}

if (-not $ready) {
    Write-Host ""
    Write-Host "WARNING: Agent 可能未成功启动" -ForegroundColor Yellow
    Write-Host "请检查: $agentDir\start-agent.bat" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "按任意键关闭..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
