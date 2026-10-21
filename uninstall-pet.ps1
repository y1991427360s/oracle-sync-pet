# 停掉桌宠、移除登录自启，并从 Claude Code 配置里摘掉桌宠的通知 hook（其他 hook 保留）
param([switch]$KeepHooks)
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'oracle-sync-common.ps1')

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '[\\/]pet\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Oracle-Sync 桌宠.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "已删除自启快捷方式: $lnk" }
else { Write-Host "没有找到自启快捷方式" }

if (-not $KeepHooks) {
    try { Write-Host ("Claude Code：" + (Update-OracleClaudeHook '' -Remove)) } catch {}
    Write-Host "Codex 的 notify 配置未改动；如需移除，请手动编辑 ~\.codex\config.toml。"
}

Write-Host "桌宠已停止。脚本文件保留在 tools\pets\，需要时可重新运行 install-pet.ps1。"
