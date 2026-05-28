# 停掉桌宠并移除登录自启
$ErrorActionPreference = 'SilentlyContinue'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'pet\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Oracle-Sync 桌宠.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "已删除自启快捷方式: $lnk" }
else { Write-Host "没有找到自启快捷方式" }

Write-Host "桌宠已停止。脚本文件保留在 tools\pets\，需要时可重新运行 install-pet.ps1。"
