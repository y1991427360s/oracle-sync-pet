Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$ErrorActionPreference = 'Stop'
$root      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$petPng    = Join-Path $PSScriptRoot 'pet.png'
$stateDir  = Join-Path $env:LOCALAPPDATA 'OracleSyncPet'
$stateFile = Join-Path $stateDir 'state.json'
$notifyDir = Join-Path $stateDir 'notify'
if (-not (Test-Path $stateDir))  { New-Item -ItemType Directory -Path $stateDir  -Force | Out-Null }
if (-not (Test-Path $notifyDir)) { New-Item -ItemType Directory -Path $notifyDir -Force | Out-Null }

# ---------- 打开/激活同步文件夹 ----------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@

function Open-SyncFolder {
    $shell = New-Object -ComObject Shell.Application
    $found = $null
    foreach ($w in $shell.Windows()) {
        try {
            $u = $w.LocationURL
            if (-not $u) { continue }
            $p = [Uri]::new($u).LocalPath.TrimEnd('\')
            if ($p -ieq $root) { $found = $w; break }
        } catch {}
    }
    if ($found) {
        $hwnd = [IntPtr]$found.HWND
        if ([Win32]::IsIconic($hwnd)) { [void][Win32]::ShowWindow($hwnd, 9) }
        $fg = [Win32]::GetForegroundWindow()
        $pidOut = 0
        $fgTid = [Win32]::GetWindowThreadProcessId($fg, [ref]$pidOut)
        $curTid = [Win32]::GetCurrentThreadId()
        [void][Win32]::AttachThreadInput($fgTid, $curTid, $true)
        [void][Win32]::SetForegroundWindow($hwnd)
        [void][Win32]::AttachThreadInput($fgTid, $curTid, $false)
    } else {
        Start-Process explorer.exe -ArgumentList "`"$root`""
    }
}

# ---------- 加载位置 ----------
$pos = [pscustomobject]@{ Left = 200.0; Top = 200.0 }
if (Test-Path $stateFile) {
    try { $pos = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

# ---------- 选择形象：优先 pet.png，否则 emoji ----------
$transformBlock = @"
      <TransformGroup>
        <ScaleTransform     x:Name="PetScale"   ScaleX="1" ScaleY="1"/>
        <ScaleTransform     x:Name="ActScale"   ScaleX="1" ScaleY="1"/>
        <RotateTransform    x:Name="PetRotate"  Angle="0"/>
        <TranslateTransform x:Name="PetTrans"   X="0" Y="0"/>
      </TransformGroup>
"@
if (Test-Path $petPng) {
    $bodyXaml = @"
    <Image x:Name="Pet" Source="$([Uri]::new($petPng).AbsoluteUri)" Width="96" Height="96" Cursor="Hand"
           RenderTransformOrigin="0.5,0.5">
      <Image.RenderTransform>$transformBlock</Image.RenderTransform>
    </Image>
"@
} else {
    $bodyXaml = @"
    <TextBlock x:Name="Pet" Text="&#x1F430;" FontSize="80" FontFamily="Segoe UI Emoji" Cursor="Hand"
               RenderTransformOrigin="0.5,0.5">
      <TextBlock.RenderTransform>$transformBlock</TextBlock.RenderTransform>
    </TextBlock>
"@
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight"
        Title="OracleSyncPet" ToolTip="左键拖动 / 点击打开 Oracle-Sync / 右键菜单">
  <Grid Margin="8">
    $bodyXaml
    <Ellipse x:Name="StatusDot" Width="18" Height="18"
             HorizontalAlignment="Right" VerticalAlignment="Bottom"
             Margin="0,0,2,2" Fill="#FF9E9E9E" Stroke="White" StrokeThickness="2"
             ToolTip="Syncthing 状态：检测中…">
      <Ellipse.Effect>
        <DropShadowEffect BlurRadius="6" ShadowDepth="1" Opacity="0.55"/>
      </Ellipse.Effect>
    </Ellipse>
    <Popup x:Name="Bubble" PlacementTarget="{Binding ElementName=Pet}" Placement="Top"
           AllowsTransparency="True" StaysOpen="True" VerticalOffset="-4" HorizontalOffset="0"
           PopupAnimation="Fade">
      <Border x:Name="BubbleBorder" Background="#FFFFFAF0" BorderBrush="#FFE0C97A"
              BorderThickness="1.5" CornerRadius="12" Padding="12,8" MaxWidth="240"
              Cursor="Hand">
        <Border.Effect>
          <DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.35"/>
        </Border.Effect>
        <TextBlock x:Name="BubbleText" FontFamily="Segoe UI Emoji, Microsoft YaHei UI"
                   FontSize="14" Foreground="#FF4A3A1B" TextWrapping="Wrap"
                   Text="该喝水啦 💧"/>
      </Border>
    </Popup>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)
$win.Left = [double]$pos.Left
$win.Top  = [double]$pos.Top

$pet         = $win.FindName('Pet')
$petScale    = $win.FindName('PetScale')
$actScale    = $win.FindName('ActScale')
$petRotate   = $win.FindName('PetRotate')
$petTrans    = $win.FindName('PetTrans')
$bubble      = $win.FindName('Bubble')
$bubbleText  = $win.FindName('BubbleText')
$bubbleBorder= $win.FindName('BubbleBorder')
$statusDot   = $win.FindName('StatusDot')

# ---------- 拖动 vs 点击 ----------
$script:startMouse = $null
$script:startLeft  = 0.0
$script:startTop   = 0.0
$script:moved      = $false

$win.Add_MouseLeftButtonDown({
    $script:startMouse = $win.PointToScreen($_.GetPosition($win))
    $script:startLeft  = $win.Left
    $script:startTop   = $win.Top
    $script:moved      = $false
    [void]$win.CaptureMouse()
})

$win.Add_MouseMove({
    if ($win.IsMouseCaptured) {
        $cur = $win.PointToScreen($_.GetPosition($win))
        $dx  = $cur.X - $script:startMouse.X
        $dy  = $cur.Y - $script:startMouse.Y
        if ([Math]::Abs($dx) -gt 4 -or [Math]::Abs($dy) -gt 4) { $script:moved = $true }
        if ($script:moved) {
            $win.Left = $script:startLeft + $dx
            $win.Top  = $script:startTop  + $dy
        }
    }
})

$win.Add_MouseLeftButtonUp({
    if ($win.IsMouseCaptured) { $win.ReleaseMouseCapture() }
    if ($script:moved) {
        @{ Left = $win.Left; Top = $win.Top } | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    } else {
        # 按一下：缩放动画 + 打开文件夹
        $pop = New-Object System.Windows.Media.Animation.DoubleAnimation 0.75, 1.0, ([TimeSpan]::FromMilliseconds(220))
        $pop.EasingFunction = New-Object System.Windows.Media.Animation.BackEase -Property @{ Amplitude = 1.5; EasingMode = 'EaseOut' }
        $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pop)
        $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
        Open-SyncFolder
    }
})

# 鼠标悬停：轻微放大
$pet.Add_MouseEnter({
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation 1.15, ([TimeSpan]::FromMilliseconds(120))
    $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $a)
    $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $a)
})
$pet.Add_MouseLeave({
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, ([TimeSpan]::FromMilliseconds(120))
    $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $a)
    $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $a)
})

# ---------- 右键菜单 ----------
$menu = New-Object System.Windows.Controls.ContextMenu
$miOpen = New-Object System.Windows.Controls.MenuItem; $miOpen.Header = '打开 Oracle-Sync'
$miOpen.Add_Click({ Open-SyncFolder })
$miReset = New-Object System.Windows.Controls.MenuItem; $miReset.Header = '回到屏幕中央'
$miReset.Add_Click({
    $win.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth  - $win.ActualWidth)  / 2
    $win.Top  = ([System.Windows.SystemParameters]::PrimaryScreenHeight - $win.ActualHeight) / 2
    @{ Left = $win.Left; Top = $win.Top } | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
})
$miExit = New-Object System.Windows.Controls.MenuItem; $miExit.Header = '退出桌宠'
$miExit.Add_Click({ $win.Close() })
$miWater = New-Object System.Windows.Controls.MenuItem; $miWater.Header = '立即提醒喝水'
$miSync  = New-Object System.Windows.Controls.MenuItem; $miSync.Header  = '查看同步状态'
$miPause = New-Object System.Windows.Controls.MenuItem; $miPause.Header = '暂停 / 恢复同步'
[void]$menu.Items.Add($miOpen)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miSync)
[void]$menu.Items.Add($miPause)
[void]$menu.Items.Add($miReset)
[void]$menu.Items.Add($miWater)
[void]$menu.Items.Add($miExit)
$win.ContextMenu = $menu

# ---------- 闲置时的呼吸动画 ----------
$breathe = New-Object System.Windows.Media.Animation.DoubleAnimation
$breathe.From = 1.0; $breathe.To = 1.12
$breathe.Duration = [System.Windows.Duration]([TimeSpan]::FromSeconds(2))
$breathe.AutoReverse = $true
$breathe.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
$petScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $breathe)
$petScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $breathe)

# ---------- 随机闲置动作 ----------
$rand = New-Object System.Random
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)

function Hop {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation 0, -28, ([TimeSpan]::FromMilliseconds(220))
    $a.AutoReverse = $true
    $a.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase -Property @{ EasingMode = 'EaseOut' }
    $petTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a)
}
function Wiggle {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation -18, 18, ([TimeSpan]::FromMilliseconds(140))
    $a.AutoReverse = $true
    $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::new(2)
    $a.From = -18
    $petRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $a)
    # 收尾归零
    $back = New-Object System.Windows.Media.Animation.DoubleAnimation 0, ([TimeSpan]::FromMilliseconds(120))
    $back.BeginTime = [TimeSpan]::FromMilliseconds(560)
    $petRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $back, 'Compose')
}
function Spin {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 360, ([TimeSpan]::FromMilliseconds(700))
    $a.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseInOut' }
    $petRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $a)
}
function Nod {
    $sx = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 1.15, ([TimeSpan]::FromMilliseconds(160))
    $sx.AutoReverse = $true
    $sy = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.85, ([TimeSpan]::FromMilliseconds(160))
    $sy.AutoReverse = $true
    $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sx)
    $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sy)
}
function Shake {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation -8, 8, ([TimeSpan]::FromMilliseconds(60))
    $a.AutoReverse = $true
    $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::new(3)
    $petTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
}

$timer.Add_Tick({
    if ($win.IsMouseCaptured -or $pet.IsMouseOver) { return }
    switch ($rand.Next(6)) {
        0 { Hop }
        1 { Wiggle }
        2 { Spin }
        3 { Nod }
        4 { Shake }
        default { } # 偶尔什么都不做
    }
    $timer.Interval = [TimeSpan]::FromSeconds($rand.Next(3, 7))
})
$timer.Start()

# ---------- 喝水提醒气泡 ----------
function Show-Bubble([string]$text, [int]$seconds = 0) {
    $bubbleText.Text = $text
    $bubble.IsOpen = $true
    Hop  # 蹦一下吸引注意
    # seconds 参数仅保留兼容旧调用；所有气泡都必须点击后才收起。
}

# 点气泡：立刻收起
$bubbleBorder.Add_MouseLeftButtonDown({
    $bubble.IsOpen = $false
    $_.Handled = $true
})

$waterMessages = @(
    '该喝水啦 💧 起来活动一下吧～',
    '咕嘟咕嘟～该喝口水了 🥤',
    '40 分钟到啦，记得补水哦 💦',
    '提醒一下：喝水时间到 ☕'
)
$waterTimer = New-Object System.Windows.Threading.DispatcherTimer
$waterTimer.Interval = [TimeSpan]::FromMinutes(30)
$waterLog = Join-Path $stateDir 'water.log'
function Write-WaterLog([string]$event, [string]$msg = '') {
    try {
        $line = "{0}  {1}  {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $event, $msg
        Add-Content -Path $waterLog -Value $line -Encoding UTF8
    } catch {}
}
$waterTimer.Add_Tick({
    try {
        $msg = $waterMessages | Get-Random
        Show-Bubble $msg
        Write-WaterLog 'fire' $msg
    } catch {}
})
$waterTimer.Start()

# 右键菜单"立即提醒喝水"
$miWater.Add_Click({
    $msg = $waterMessages | Get-Random
    Show-Bubble $msg
    Write-WaterLog 'manual' $msg
})

# ---------- 外部任务完成通知 ----------
# 任何程序往 $notifyDir 里写一个 *.txt，pet 就读出来弹气泡然后删掉。
# 用 tools\pets\notify-pet.ps1 作为投递入口。
$notifyPoll = New-Object System.Windows.Threading.DispatcherTimer
$notifyPoll.Interval = [TimeSpan]::FromSeconds(2)
$notifyPoll.Add_Tick({
    try {
        $files = Get-ChildItem -Path $notifyDir -Filter '*.txt' -File -ErrorAction Stop |
                 Sort-Object CreationTime
    } catch { return }
    foreach ($f in $files) {
        $text = $null
        try { $text = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { }
        Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($text)) { $text = '✅ 任务完成' }
        try { Show-Bubble $text.Trim() } catch {}
    }
})
$notifyPoll.Start()

# ---------- Syncthing 同步状态 ----------
# 从本机 Syncthing config.xml 读 API key 与目标 folder id，定期轮询 REST，
# 在桌宠右下角小圆点上反映状态（绿=已同步 / 黄脉动=同步中 / 红=异常 / 灰=未知）。
$script:syncApiKey   = $null
$script:syncFolderId = $null
$script:syncLastKind = $null   # 上次稳定状态，用于"状态变化时弹气泡"

$cfgPath = Join-Path $env:LOCALAPPDATA 'Syncthing\config.xml'
if (Test-Path $cfgPath) {
    try {
        [xml]$cfg = Get-Content $cfgPath -Raw
        $script:syncApiKey = $cfg.configuration.gui.apikey
        foreach ($f in @($cfg.configuration.folder)) {
            $fp = $null
            try { $fp = (Resolve-Path $f.path -ErrorAction Stop).Path.TrimEnd('\') } catch { $fp = ($f.path).TrimEnd('\') }
            if ($fp -and ($fp -ieq $root)) { $script:syncFolderId = $f.id; break }
        }
        if (-not $script:syncFolderId) {
            # 兜底：按已知 id 试一下
            $script:syncFolderId = 'oracle-sync'
        }
    } catch {}
}

# 状态点颜色
$colorOk      = '#FF4CAF50'  # 绿
$colorSync    = '#FFFFC107'  # 黄
$colorWarn    = '#FFFF9800'  # 橙：已同步但无对端在线
$colorError   = '#FFE53935'  # 红
$colorPaused  = '#FF03A9F4'  # 蓝：用户主动暂停
$colorUnknown = '#FF9E9E9E'  # 灰

# 黄色脉动动画（同步中用）
$pulseAnim = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.4, ([TimeSpan]::FromMilliseconds(700))
$pulseAnim.AutoReverse = $true
$pulseAnim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever

function Set-StatusDot([string]$kind, [string]$tooltip) {
    $color = switch ($kind) {
        'ok'      { $colorOk }
        'sync'    { $colorSync }
        'warn'    { $colorWarn }
        'error'   { $colorError }
        'paused'  { $colorPaused }
        default   { $colorUnknown }
    }
    $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color))
    $statusDot.Fill = $brush
    $statusDot.ToolTip = $tooltip
    if ($kind -eq 'sync') {
        $statusDot.BeginAnimation([System.Windows.Controls.Control]::OpacityProperty, $pulseAnim)
    } else {
        $statusDot.BeginAnimation([System.Windows.Controls.Control]::OpacityProperty, $null)
        $statusDot.Opacity = 1.0
    }
}

function Test-SyncthingPort {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ar = $c.BeginConnect('127.0.0.1', 8384, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(300)
        if ($ok -and $c.Connected) { $c.EndConnect($ar); $c.Close(); return $true }
        $c.Close(); return $false
    } catch { return $false }
}

function Get-HumanBytes([long]$n) {
    if ($n -lt 1KB)  { return "$n B" }
    if ($n -lt 1MB)  { return ('{0:N1} KB' -f ($n / 1KB)) }
    if ($n -lt 1GB)  { return ('{0:N1} MB' -f ($n / 1MB)) }
    return ('{0:N2} GB' -f ($n / 1GB))
}

function Poll-SyncStatus {
    if (-not $script:syncApiKey -or -not $script:syncFolderId) {
        Set-StatusDot 'unknown' '未找到 Syncthing 配置'
        return @{ kind = 'unknown' }
    }
    if (-not (Test-SyncthingPort)) {
        Set-StatusDot 'error' 'Syncthing 未运行（127.0.0.1:8384 无响应）'
        return @{ kind = 'offline' }
    }
    $headers = @{ 'X-API-Key' = $script:syncApiKey }
    try {
        $fcfg = Invoke-RestMethod -Uri "http://127.0.0.1:8384/rest/config/folders/$($script:syncFolderId)" -Headers $headers -TimeoutSec 2
    } catch {
        Set-StatusDot 'error' ("Syncthing 无响应：" + $_.Exception.Message)
        return @{ kind = 'error' }
    }
    if ($fcfg.paused) {
        $tip = '已暂停同步（右键 → 暂停 / 恢复同步 可恢复）'
        Set-StatusDot 'paused' $tip
        return @{ kind = 'paused'; tip = $tip }
    }
    try {
        $st = Invoke-RestMethod -Uri "http://127.0.0.1:8384/rest/db/status?folder=$($script:syncFolderId)" -Headers $headers -TimeoutSec 2
        $cn = Invoke-RestMethod -Uri 'http://127.0.0.1:8384/rest/system/connections' -Headers $headers -TimeoutSec 2
    } catch {
        Set-StatusDot 'error' ("Syncthing 无响应：" + $_.Exception.Message)
        return @{ kind = 'error' }
    }
    $state = [string]$st.state
    $needB = [long]($st.needBytes)
    $needF = [int]($st.needFiles + $st.needDirectories + $st.needSymlinks + $st.needDeletes)
    $connected = 0
    if ($cn.connections) {
        foreach ($p in $cn.connections.PSObject.Properties) {
            if ($p.Value.connected) { $connected++ }
        }
    }
    $kind = 'unknown'; $tip = ''
    if ($state -eq 'syncing' -or $state -eq 'scanning') {
        $kind = 'sync'
        $label = if ($state -eq 'scanning') { '扫描中' } else { '同步中' }
        if ($needB -gt 0 -or $needF -gt 0) {
            $tip = "$label · 剩 $(Get-HumanBytes $needB) / $needF 项"
        } else {
            $tip = "$label…"
        }
    } elseif ($state -eq 'error') {
        $kind = 'error'; $tip = "同步出错：$($st.error)"
    } elseif ($needB -gt 0 -or $needF -gt 0) {
        $kind = 'sync'
        $tip = "等待同步 · 剩 $(Get-HumanBytes $needB) / $needF 项"
    } else {
        if ($connected -gt 0) {
            $kind = 'ok'; $tip = "已同步 · 与 $connected 台设备相连"
        } else {
            $kind = 'warn'; $tip = '已同步 · 暂无对端在线'
        }
    }
    Set-StatusDot $kind $tip
    return @{ kind = $kind; tip = $tip; needBytes = $needB; needFiles = $needF; connected = $connected; state = $state }
}

function Update-SyncStatus {
    $cur = Poll-SyncStatus
    $k = $cur.kind
    $prev = $script:syncLastKind
    if ($prev -and $prev -ne $k) {
        switch ("$prev->$k") {
            'ok->sync'      { Show-Bubble '🔄 开始同步…' }
            'warn->sync'    { Show-Bubble '🔄 开始同步…' }
            'unknown->sync' { }
            'sync->ok'      { Show-Bubble '✅ Oracle-Sync 同步完成' }
            'sync->warn'    { Show-Bubble '✅ 已同步（暂无对端在线）' }
            'ok->offline'   { Show-Bubble '⚠️ Syncthing 不在跑了' }
            'sync->offline' { Show-Bubble '⚠️ Syncthing 不在跑了' }
            'ok->error'     { Show-Bubble '⚠️ 同步出错，看下小圆点' }
            'sync->error'   { Show-Bubble '⚠️ 同步出错，看下小圆点' }
            'paused->ok'    { Show-Bubble '▶ 已恢复同步' }
            'paused->sync'  { Show-Bubble '▶ 已恢复同步' }
            'paused->warn'  { Show-Bubble '▶ 已恢复同步（暂无对端）' }
        }
    }
    $script:syncLastKind = $k
}

$syncTimer = New-Object System.Windows.Threading.DispatcherTimer
$syncTimer.Interval = [TimeSpan]::FromSeconds(5)
$syncTimer.Add_Tick({
    # 单次 Tick 异常不能让 DispatcherTimer 静默停掉——否则状态就永远卡在上一次值。
    try { Update-SyncStatus }
    catch { try { Set-StatusDot 'unknown' ("状态轮询异常：" + $_.Exception.Message) } catch {} }
})
# 启动时先跑一次（不弹"完成"气泡）
$win.Add_SourceInitialized({
    try { Update-SyncStatus } catch {}
    $syncTimer.Start()
})

# 右键菜单"查看同步状态"
$miSync.Add_Click({
    $cur = Poll-SyncStatus
    if ($cur.tip) { Show-Bubble $cur.tip } else { Show-Bubble 'Syncthing 状态：未知' }
})

# 右键菜单"暂停 / 恢复同步"——根据当前是否暂停切换
$miPause.Add_Click({
    if (-not $script:syncApiKey -or -not $script:syncFolderId) {
        Show-Bubble '找不到 Syncthing 配置，无法切换'
        return
    }
    if (-not (Test-SyncthingPort)) {
        Show-Bubble 'Syncthing 没在跑，先把它启动起来'
        return
    }
    $headers = @{ 'X-API-Key' = $script:syncApiKey; 'Content-Type' = 'application/json' }
    try {
        $fcfg = Invoke-RestMethod -Uri "http://127.0.0.1:8384/rest/config/folders/$($script:syncFolderId)" -Headers $headers -TimeoutSec 2
        $newPaused = -not [bool]$fcfg.paused
        $body = (@{ paused = $newPaused } | ConvertTo-Json -Compress)
        Invoke-RestMethod -Method Patch -Uri "http://127.0.0.1:8384/rest/config/folders/$($script:syncFolderId)" -Headers $headers -Body $body -TimeoutSec 3 | Out-Null
        if ($newPaused) { Show-Bubble '⏸ 已暂停 Oracle-Sync 同步' } else { Show-Bubble '▶ 已恢复 Oracle-Sync 同步' }
        Update-SyncStatus
    } catch {
        Show-Bubble ("切换失败：" + $_.Exception.Message)
    }
})

# 打开菜单前刷新"暂停 / 恢复"标签
$menu.Add_Opened({
    if ($script:syncLastKind -eq 'paused') { $miPause.Header = '▶ 恢复同步' }
    else                                    { $miPause.Header = '⏸ 暂停同步' }
})

# 单实例：互斥锁
$mutex = New-Object System.Threading.Mutex($false, 'Global\OracleSyncPet')
if (-not $mutex.WaitOne(0)) { return }

[void]$win.ShowDialog()
$mutex.ReleaseMutex()
