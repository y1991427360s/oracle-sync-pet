# 任何外部程序想让桌宠弹气泡，调用本脚本即可。
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File notify-pet.ps1 -Message "✅ 任务完成"
param(
    [Parameter(Mandatory = $true)][string]$Message
)
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:LOCALAPPDATA 'OracleSyncPet\notify'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$file = Join-Path $dir ([Guid]::NewGuid().ToString() + '.txt')
Set-Content -Path $file -Value $Message -Encoding UTF8
