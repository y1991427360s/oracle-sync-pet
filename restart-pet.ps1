# 重启桌宠：结束现有 pet.ps1 进程，再交给资源管理器启动 pet.vbs。
# AI 工具 / 终端里重启桌宠请用这个脚本，不要直接 Start-Process pet.vbs——
# 那样桌宠会成为调用方的子进程，调用方退出或清理后台任务时会被连带强杀（exit.log 只有 start、没有任何退出记录）。
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-sync-common.ps1')
$vbs = Join-Path $PSScriptRoot 'pet.vbs'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '[\\/]pet\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

if (Start-OraclePet $vbs) { Write-Host '已通过资源管理器启动桌宠。' }
else { Write-Warning '资源管理器代启动失败，已直接启动；调用方退出时桌宠可能被一起结束。' }