# 在桌面创建快捷方式（打开 Oracle-Sync 同步文件夹、一键重启桌宠）。每台新电脑跑一次即可。
$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot
$vbs = Join-Path $toolsDir 'open-sync-folder.vbs'
$restartVbs = Join-Path $toolsDir 'restart-pet.vbs'
$icon = Join-Path $toolsDir 'pet.ico'

if (-not (Test-Path $icon)) {
    $icon = "$env:SystemRoot\System32\imageres.dll,3"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell

# 1. 打开同步文件夹快捷方式
$lnkPath = Join-Path $desktop 'Oracle-Sync.lnk'
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = 'wscript.exe'
$lnk.Arguments = "`"$vbs`""
$lnk.WorkingDirectory = $toolsDir
$lnk.IconLocation = $icon
$lnk.Description = '点击打开/激活 Oracle-Sync 同步文件夹'
$lnk.Save()
Write-Host "已在桌面生成: $lnkPath"

# 2. 一键重启/复位桌宠快捷方式
$restartLnkPath = Join-Path $desktop '重启桌宠(复位).lnk'
$lnkRestart = $shell.CreateShortcut($restartLnkPath)
$lnkRestart.TargetPath = 'wscript.exe'
$lnkRestart.Arguments = "`"$restartVbs`""
$lnkRestart.WorkingDirectory = $toolsDir
$lnkRestart.IconLocation = "$env:SystemRoot\System32\shell32.dll,238"
$lnkRestart.Description = '双击一键重启桌宠、清除喝水滤镜并将桌宠复位至屏幕中央'
$lnkRestart.Save()
Write-Host "已在桌面生成: $restartLnkPath"
