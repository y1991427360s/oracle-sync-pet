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
        # hook JSON 是 UTF-8，但 Windows PowerShell 在脚本运行前就按系统代码页 936 解码了 stdin，
        # 中文会变成“闈㈣瘯”这类乱码；按 936 还原字节后严格按 UTF-8 重解，失败则保持原样
        if ($raw -and $raw -match '[^\x00-\x7F]') {
            try {
                $bytes = [Text.Encoding]::GetEncoding(936).GetBytes($raw)
                $raw = (New-Object System.Text.UTF8Encoding $false, $true).GetString($bytes)
            } catch {}
        }
        $cwd = $null
        if ($raw) {
            try { $cwd = [string]($raw | ConvertFrom-Json).cwd } catch {
                if ($raw -match '"cwd"\s*:\s*"([^"]+)"') { $cwd = $Matches[1] -replace '\\\\', '\' }
            }
        }
        # Claude Code 给 hook 的项目目录环境变量不经过 stdin 解码，中文最可靠，优先使用
        if ($Source -eq 'Claude Code' -and $env:CLAUDE_PROJECT_DIR) { $cwd = $env:CLAUDE_PROJECT_DIR }
        if ($cwd) { $project = Split-Path -Leaf $cwd.TrimEnd('\', '/') }
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
