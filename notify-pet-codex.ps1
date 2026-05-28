param([string]$Json)
$ErrorActionPreference = 'SilentlyContinue'
$logPath = Join-Path $env:LOCALAPPDATA 'OracleSyncPet\codex-notify.log'

function Write-NotifyLog([string]$text) {
    try {
        $dir = Split-Path -Parent $logPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $logPath -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text) -Encoding UTF8
    } catch {}
}

if (-not $Json) {
    try {
        if (-not [Console]::IsInputRedirected) {
            Write-NotifyLog 'no json argument and stdin is not redirected'
            return
        }
        $Json = [Console]::In.ReadToEnd()
    } catch {
        Write-NotifyLog ("failed to read stdin: " + $_.Exception.Message)
        return
    }
}

if ([string]::IsNullOrWhiteSpace($Json)) {
    Write-NotifyLog 'empty json payload'
    return
}

try { $obj = $Json | ConvertFrom-Json -ErrorAction Stop }
catch {
    Write-NotifyLog ("json parse failed: " + $_.Exception.Message)
    return
}

if ($obj.type -ne 'agent-turn-complete') {
    Write-NotifyLog ("ignored event type: " + [string]$obj.type)
    return
}

$msg = [char]0x2705 + ' Codex ' + [char]0x4EFB + [char]0x52A1 + [char]0x5B8C + [char]0x6210
$last = $obj.'last-assistant-message'
if ($last) {
    $preview = ($last -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 60) { $preview = $preview.Substring(0, 60) + '...' }
    if ($preview) { $msg = [char]0x2705 + ' Codex: ' + $preview }
}
& (Join-Path $PSScriptRoot 'notify-pet.ps1') -Message $msg
Write-NotifyLog ("sent: " + $msg)
