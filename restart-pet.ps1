param([switch]$KeepPos)

# 重启桌宠：结束现有 pet.ps1 进程（同时自动清除喝水滤镜），重置坐标至屏幕安全区，再交给资源管理器启动 pet.vbs。
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-sync-common.ps1')
$vbs = Join-Path $PSScriptRoot 'pet.vbs'
$stateFile = Join-Path $env:LOCALAPPDATA 'OracleSyncPet\state.json'

# 1. 结束所有正在运行的桌宠进程（同时会强行关闭喝水滤镜等所有附属窗口）
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '[\\/]pet\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. 若未指定 -KeepPos，重置位置到主屏幕显眼居中位置，防止宠物被拖到死角或副屏盲区
if (-not $KeepPos -and (Test-Path $stateFile)) {
    try {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.Left = 1200
        $state.Top  = 600
        $state.Dock = $null
        $state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    } catch {}
}

Start-Sleep -Milliseconds 800

if (Start-OraclePet $vbs) { Write-Host '已通过资源管理器重启桌宠并复位到屏幕中央。' }
else { Write-Warning '资源管理器代启动失败，已直接启动；调用方退出时桌宠可能被一起结束。' }