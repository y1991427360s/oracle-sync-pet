# 在桌面创建"打开 Oracle-Sync"快捷方式。每台新电脑跑一次即可。
$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot
$vbs = Join-Path $toolsDir 'open-sync-folder.vbs'
$icon = Join-Path $toolsDir 'pet.ico'

if (-not (Test-Path $icon)) {
    # 没有自定义图标时退化为系统文件夹图标
    $icon = "$env:SystemRoot\System32\imageres.dll,3"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'Oracle-Sync.lnk'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = 'wscript.exe'
$lnk.Arguments = "`"$vbs`""
$lnk.WorkingDirectory = $toolsDir
$lnk.IconLocation = $icon
$lnk.Description = '点击打开/激活 Oracle-Sync 同步文件夹'
$lnk.Save()

Write-Host "已在桌面生成: $lnkPath"
Write-Host "如需替换为自定义桌宠图标，把 .ico 文件放到 $toolsDir\pet.ico 后重跑本脚本。"
