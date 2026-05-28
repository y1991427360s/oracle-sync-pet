# 在当前 Windows 用户的"启动"文件夹里放快捷方式，登录即自动启动桌宠。
# 每台新电脑跑一次即可。
$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot
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
Write-Host ""
Write-Host "立即启动桌宠..."
Start-Process wscript.exe -ArgumentList "`"$vbs`""
Write-Host "完成。桌宠会出现在屏幕上，左键拖动 / 单击打开同步文件夹 / 右键有菜单。"
