# 离屏渲染桌宠界面（桌宠本体 / 气泡 / 右键菜单）为 PNG，改样式后不用重启桌宠就能看效果。
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\preview-ui.ps1 [-OutDir <目录>] [-NoOpen]
# 原理: 截取 pet.ps1 里 "# region UI-XAML" 与 "# region UI-MENU" 两段代码执行，不启动桌宠本身。
param([string]$OutDir = (Join-Path $env:TEMP 'OracleSyncPetPreview'), [switch]$NoOpen)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ErrorActionPreference = 'Stop'

$petScript = Join-Path $PSScriptRoot 'pet.ps1'
$text = [IO.File]::ReadAllText($petScript)
function Get-Region([string]$name) {
    $m = [regex]::Match($text, "(?s)# region $name[^\n]*\n(.*?)# endregion $name")
    if (-not $m.Success) { throw "pet.ps1 里找不到 region $name" }
    return $m.Groups[1].Value
}
$petPng = Join-Path $PSScriptRoot 'pet.png'
Invoke-Expression (Get-Region 'UI-XAML')
$win = [Windows.Markup.XamlReader]::Parse($xaml)
Invoke-Expression (Get-Region 'UI-MENU')
$miInfo.Header = "已同步 · 与 1 台设备相连`n最近同步：今天 14:32 · 示例文件.md"
$miConflict.Header = '同步冲突文件（2）'
$miConflict.Visibility = 'Visible'
$miWaterDone.IsEnabled = $true

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$bg = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xB8, 0xC6, 0xDB))

function Save-Png($visual, [System.Windows.Size]$size, [string]$path) {
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]($size.Width * 2)), ([int]($size.Height * 2)), 192, 192, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen(); $dc.DrawRectangle($bg, $null, [System.Windows.Rect]::new($size)); $dc.Close()
    $bmp.Render($dv); $bmp.Render($visual)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($path); try { $enc.Save($fs) } finally { $fs.Close() }
    Write-Host "已生成 $path"
}
function Render-Element($el, [string]$path) {
    $el.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $el.Arrange([System.Windows.Rect]::new($el.DesiredSize))
    $el.UpdateLayout()
    Save-Png $el $el.DesiredSize $path
}

# 气泡（Popup 内容）要先从 Popup 里摘出来才能单独渲染
$bubble = $win.FindName('Bubble')
$win.FindName('BubbleText').Text = '✅ Claude Code 任务完成 · pets'
$win.FindName('BubbleHint').Text = '点击查看下一条（还有 2 条）'
$bubbleRoot = $bubble.Child; $bubble.Child = $null
$grid = $win.Content; $win.Content = $null
$grid.Resources = $win.Resources

Render-Element $grid       (Join-Path $OutDir 'pet.png')
Render-Element $bubbleRoot (Join-Path $OutDir 'bubble.png')
Render-Element $menu       (Join-Path $OutDir 'menu.png')
if (-not $NoOpen) { Start-Process explorer.exe -ArgumentList "`"$OutDir`"" }
