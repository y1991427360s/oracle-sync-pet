# 任何外部程序想让桌宠弹气泡，调用本脚本即可。
# 用法 1: powershell -NoProfile -ExecutionPolicy Bypass -File notify-pet.ps1 -Message "✅ 任务完成"
# 用法 2: powershell -NoProfile -ExecutionPolicy Bypass -File notify-pet.ps1 -Source "Claude Code"
#         作为 Claude Code 的 Stop hook 使用时，会从 stdin 读取 hook JSON，取 cwd 的文件夹名作为项目名。
param(
    [string]$Message,
    [string]$Source
)
$ErrorActionPreference = 'SilentlyContinue'
$stateDir = Join-Path $env:LOCALAPPDATA 'OracleSyncPet'
$dir = Join-Path $stateDir 'notify'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

if (-not $Message) {
    $project = $null
    try {
        # powershell -File 有时会先把重定向进来的 stdin 读进 $input，此时 [Console]::In 已经是空的
        $raw = @($input) -join "`n"
        if (-not $raw -and [Console]::IsInputRedirected) { $raw = [Console]::In.ReadToEnd() }
        if ($raw) {
            $cwd = $null
            try { $cwd = [string]($raw | ConvertFrom-Json).cwd } catch {
                if ($raw -match '"cwd"\s*:\s*"([^"]+)"') { $cwd = $Matches[1] -replace '\\\\', '\' }
            }
            if ($cwd) { $project = Split-Path -Leaf $cwd.TrimEnd('\', '/') }
        }
    } catch {}
    $Message = '✅ '
    if ($Source)  { $Message += "$Source " }
    $Message += '任务完成'
    if ($project) { $Message += " · $project" }
}

# 先写临时文件再改名，避免桌宠读到写了一半的内容
$file = Join-Path $dir ([Guid]::NewGuid().ToString() + '.txt')
Set-Content -Path "$file.tmp" -Value $Message -Encoding UTF8
Move-Item -LiteralPath "$file.tmp" -Destination $file -Force
try {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path (Join-Path $stateDir 'notify-pet.log') -Value $line -Encoding UTF8
} catch {}
