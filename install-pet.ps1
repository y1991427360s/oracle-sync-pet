# 在当前 Windows 用户的"启动"文件夹里放快捷方式，登录即自动启动桌宠；
# 同时给 Claude Code 接上"任务完成"气泡提醒（按本机实际路径写入，不覆盖其他 hook）。
# 每台新电脑跑一次即可；重复运行也安全。加 -NoHooks 只装桌宠、不改 Claude/Codex 配置。
param([switch]$NoHooks)
$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot
. (Join-Path $toolsDir 'oracle-sync-common.ps1')
$vbs = Join-Path $toolsDir 'pet.vbs'
if (-not (Test-Path $vbs)) { throw "找不到 $vbs" }

$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'Oracle-Sync 桌宠.lnk'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath       = 'wscript.exe'
$lnk.Arguments        = "`"$vbs`""
$lnk.WorkingDirectory = $toolsDir
$lnk.IconLocation     = "$env:SystemRoot\System32\imageres.dll,3"
$lnk.Description      = 'Oracle-Sync 桌面宠物（开机自启）'
$lnk.Save()
Write-Host "已安装登录自启快捷方式: $lnkPath"

if (-not $NoHooks) {
    Write-Host ""
    # Claude Code：追加 Stop hook（会先备份 settings.json）
    try { Write-Host ("Claude Code：" + (Update-OracleClaudeHook (Join-Path $toolsDir 'notify-pet.ps1'))) }
    catch { Write-Warning ("Claude Code hook 配置失败：" + $_.Exception.Message) }

    # Codex：notify 只能有一个。已被别的程序占用时不改，只提示。
    $codexCfg = Join-Path $env:USERPROFILE '.codex\config.toml'
    $codexNotify = Join-Path $toolsDir 'notify-pet-codex.ps1'
    if (Test-Path $codexCfg) {
        $toml = [IO.File]::ReadAllText($codexCfg)
        if ($toml -match 'notify-pet-codex') {
            Write-Host "Codex：已配置桌宠通知，跳过"
        } elseif ($toml -match '(?m)^\s*notify\s*=') {
            Write-Host "Codex：config.toml 里的 notify 已被其他程序使用，未修改。如需桌宠提醒，可让那个程序转调：$codexNotify"
        } else {
            $p = $codexNotify.Replace('\', '\')
            $line = "notify = [`"powershell`", `"-NoProfile`", `"-ExecutionPolicy`", `"Bypass`", `"-File`", `"$p`"]`r`n"
            Copy-Item $codexCfg ("$codexCfg.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
            [IO.File]::WriteAllText($codexCfg, $line + $toml, (New-Object System.Text.UTF8Encoding $false))
            Write-Host "Codex：已在 $codexCfg 顶部写入 notify"
        }
    }
    Write-Host "提示：已经开着的 claude / codex 会话不会生效，需要新开一个。"
}

Write-Host ""
Write-Host "立即启动桌宠..."
if (-not (Start-OraclePet $vbs)) { Write-Warning "未能交给资源管理器启动，已直接启动；关闭当前终端/工具时桌宠可能被一起结束。" }
Write-Host "完成。桌宠会出现在屏幕上，左键拖动 / 单击打开同步文件夹 / 右键有菜单。"
