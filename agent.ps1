# Windows Agent v2 — async, non-blocking, auto-recovery
# Usage: powershell -ExecutionPolicy Bypass -File agent.ps1

param([string]$SharedDir = "")

$ErrorActionPreference = "Continue"
$script:agentPid = $PID

if (-not $SharedDir) { $SharedDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$HeartbeatFile = Join-Path $SharedDir "sys-heartbeat.json"
$ResultFile    = Join-Path $SharedDir "sys-result.json"
$ShotFile      = Join-Path $SharedDir "sys-shot-result.png"

# Track running jobs: key=filename, value=@{job, path, startTime, timeout}
$script:runningJobs = @{}

function Write-Log { param([string]$Msg); Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Msg) }

function Write-Result($data) {
    try {
        $data | ConvertTo-Json -Compress | Set-Content -Path $ResultFile -Encoding UTF8
    } catch {
        # File might be locked, retry once
        Start-Sleep -Milliseconds 200
        try { $data | ConvertTo-Json -Compress | Set-Content -Path $ResultFile -Encoding UTF8 } catch {}
    }
}

function Write-Heartbeat {
    try {
        @{ status = "alive"; timestamp = (Get-Date -Format "o"); pid = $agentPid; type = "powershell"; jobs = $script:runningJobs.Count; uptime = [int]((Get-Date) - $script:startTime).TotalSeconds } |
            ConvertTo-Json -Compress | Set-Content -Path $HeartbeatFile -Encoding UTF8
    } catch {}
}

function Start-CommandJob($filePath) {
    try {
        $task = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Log "JSON parse error: $_"
        Write-Result(@{ success = $false; error = "JSON parse failed"; timestamp = (Get-Date -Format "o") })
        Remove-Item $filePath -Force -ErrorAction SilentlyContinue
        return
    }

    $cmd     = $task.command
    $timeout = if ($task.timeout) { [int]$task.timeout } else { 60 }
    $cwd     = $task.cwd

    Write-Log "Start job: $cmd"

    $job = Start-Job -Name "cmd-$((Get-Date).Ticks)" -ScriptBlock {
        param($cmd, $cwd, $timeout)
        try {
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo.FileName = "cmd.exe"
            $proc.StartInfo.Arguments = "/c $cmd"
            $proc.StartInfo.UseShellExecute = $false
            $proc.StartInfo.RedirectStandardOutput = $true
            $proc.StartInfo.RedirectStandardError = $true
            $proc.StartInfo.CreateNoWindow = $true
            if ($cwd) { $proc.StartInfo.WorkingDirectory = $cwd }
            $proc.Start() | Out-Null
            $finished = $proc.WaitForExit($timeout * 1000)
            if (-not $finished) {
                $proc.Kill()
                return @{ success = $false; error = "Timeout ($timeout s)"; stdout = ""; stderr = "" }
            }
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $stdout = if ($stdout.Length -gt 50000) { $stdout.Substring(0, 50000) + "...[truncated]" } else { $stdout }
            $stderr = if ($stderr.Length -gt 10000) { $stderr.Substring(0, 10000) + "...[truncated]" } else { $stderr }
            return @{ success = ($proc.ExitCode -eq 0); exitCode = $proc.ExitCode; stdout = $stdout; stderr = $stderr }
        } catch {
            return @{ success = $false; error = "$_"; stdout = ""; stderr = "" }
        }
    } -ArgumentList $cmd, $cwd, $timeout

    $script:runningJobs[$filePath] = @{
        job       = $job
        startTime = Get-Date
        timeout   = $timeout + 5  # extra 5s grace
    }
}

function Start-ScreenshotJob($filePath) {
    try { $task = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Remove-Item $filePath -Force -ErrorAction SilentlyContinue; return }
    $maxWidth = if ($task.max_width) { [int]$task.max_width } else { 1920 }
    Write-Log "Screenshot... (async)"

    $job = Start-Job -Name "shot-$((Get-Date).Ticks)" -ScriptBlock {
        param($maxWidth, $ShotFile)
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen
            $bounds = $screen.Bounds
            $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
            if ($bounds.Width -gt $maxWidth) {
                $ratio = $maxWidth / $bounds.Width
                $scaled = New-Object System.Drawing.Bitmap($maxWidth, [int]($bounds.Height * $ratio))
                $g2 = [System.Drawing.Graphics]::FromImage($scaled)
                $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g2.DrawImage($bitmap, 0, 0, $maxWidth, [int]($bounds.Height * $ratio))
                $g2.Dispose(); $bitmap.Dispose(); $bitmap = $scaled
            }
            $bitmap.Save($ShotFile, [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose(); $graphics.Dispose()
            return @{ success = $true; action = "screenshot"; size = @($bounds.Width, $bounds.Height) }
        } catch {
            return @{ success = $false; error = "Screenshot failed: $_" }
        }
    } -ArgumentList $maxWidth, $ShotFile

    $script:runningJobs[$filePath] = @{ job = $job; startTime = Get-Date; timeout = 30; isScreenshot = $true }
}

function Check-Jobs {
    $toRemove = @()
    foreach ($key in $script:runningJobs.Keys) {
        $entry = $script:runningJobs[$key]
        $job = $entry.job

        if ($job.State -eq "Completed") {
            $result = $job | Receive-Job
            $job | Remove-Job -Force
            $toRemove += $key

            if (-not $entry.isScreenshot) {
                $result["timestamp"] = (Get-Date -Format "o")
                Write-Result($result)
                Write-Log "Job done: exit=$($result.exitCode)"
            }
            Remove-Item $key -Force -ErrorAction SilentlyContinue

        } elseif ($job.State -eq "Failed") {
            Write-Log "Job failed: $($job.ChildJobs[0].Error)"
            Write-Result(@{ success = $false; error = "Job crashed"; timestamp = (Get-Date -Format "o") })
            $job | Remove-Job -Force
            $toRemove += $key
            Remove-Item $key -Force -ErrorAction SilentlyContinue

        } elseif (((Get-Date) - $entry.startTime).TotalSeconds -gt $entry.timeout) {
            Write-Log "Job timeout, killing..."
            $job | Stop-Job -PassThru | Remove-Job -Force
            Write-Result(@{ success = $false; error = "Job timeout (${$entry.timeout}s)"; timestamp = (Get-Date -Format "o") })
            $toRemove += $key
            Remove-Item $key -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($k in $toRemove) { $script:runningJobs.Remove($k) }
}

function Clean-StaleFiles {
    # Remove cmd files older than 10 minutes that have no active job
    $stale = @(Get-ChildItem $SharedDir -Filter "sys-cmd-*.json" -ErrorAction SilentlyContinue | Where-Object {
        ($_.LastWriteTime -lt (Get-Date).AddMinutes(-10)) -and (-not $script:runningJobs.ContainsKey($_.FullName))
    })
    foreach ($f in $stale) {
        Write-Log "Removing stale file: $($f.Name)"
        Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Start-NewJobs {
    $cmdFiles = @(Get-ChildItem $SharedDir -Filter "sys-cmd-*.json" -ErrorAction SilentlyContinue | Sort-Object Name | Where-Object {
        -not $script:runningJobs.ContainsKey($_.FullName)
    })
    $shotFiles = @(Get-ChildItem $SharedDir -Filter "sys-shot-*.json" -ErrorAction SilentlyContinue | Sort-Object Name | Where-Object {
        -not $script:runningJobs.ContainsKey($_.FullName)
    })

    # Limit concurrent jobs to prevent overload
    $maxJobs = 3
    foreach ($f in $cmdFiles) {
        if (($script:runningJobs.Count - $script:runningJobs.Keys.Where({$script:runningJobs[$_].isScreenshot}).Count) -ge $maxJobs) { break }
        Start-CommandJob $f.FullName
    }
    foreach ($f in $shotFiles) {
        if ($script:runningJobs.Count -ge ($maxJobs + 1)) { break }
        Start-ScreenshotJob $f.FullName
    }
}

# ── Main ──
$script:startTime = Get-Date
Write-Log "========================================"
Write-Log "Windows Agent v2 (async) started"
Write-Log "SharedDir: $SharedDir"
Write-Log "PID: $agentPid"
Write-Log "========================================"

if (-not (Test-Path $SharedDir)) { New-Item -Path $SharedDir -ItemType Directory -Force | Out-Null }
Write-Heartbeat
$lastHb = Get-Date; $hbInterval = 10; $lastClean = Get-Date

Write-Log "Polling... (async mode)"

try {
    while ($true) {
        Start-NewJobs
        Check-Jobs
        if (((Get-Date) - $lastHb).TotalSeconds -gt $hbInterval) { Write-Heartbeat; $lastHb = Get-Date }
        if (((Get-Date) - $lastClean).TotalMinutes -gt 5) { Clean-StaleFiles; $lastClean = Get-Date }
        Start-Sleep -Milliseconds 500
    }
} finally {
    # Kill all running jobs
    foreach ($key in $script:runningJobs.Keys) {
        $script:runningJobs[$key].job | Stop-Job -PassThru | Remove-Job -Force
    }
    @{ status = "stopped"; timestamp = (Get-Date -Format "o") } | ConvertTo-Json | Set-Content $HeartbeatFile -Encoding UTF8
    Write-Log "Agent stopped."
}
