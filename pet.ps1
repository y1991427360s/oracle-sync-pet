param([switch]$WaterPreview)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$ErrorActionPreference = 'Stop'
$root      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$petPng    = Join-Path $PSScriptRoot 'pet.png'
$stateDir  = Join-Path $env:LOCALAPPDATA 'OracleSyncPet'
$stateFile = Join-Path $stateDir 'state.json'
$notifyDir = Join-Path $stateDir 'notify'
if (-not (Test-Path $stateDir))  { New-Item -ItemType Directory -Path $stateDir  -Force | Out-Null }
if (-not (Test-Path $notifyDir)) { New-Item -ItemType Directory -Path $notifyDir -Force | Out-Null }

# ---------- 退出原因日志 ----------
# 记录每次进程为什么结束：菜单退出 / 窗口关闭 / 未处理异常 / 进程正常退出。
# 若只有"启动"没有任何退出记录，说明进程是被外部强制结束（TerminateProcess），无法被脚本捕获。
$exitLog = Join-Path $stateDir 'exit.log'
function Write-ExitLog([string]$msg) {
    try {
        $line = "{0}  pid={1}  {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $msg
        Add-Content -Path $exitLog -Value $line -Encoding UTF8
    } catch {}
}
Write-ExitLog 'start'
[AppDomain]::CurrentDomain.add_ProcessExit({ Write-ExitLog 'process exit (normal)' })

# ---------- 打开/激活同步文件夹 ----------
# Win32 P/Invoke 类型只在"点击打开文件夹"时才用得到。Add-Type 底层会拉起 csc.exe
# 编译，在冷启动时要花一两秒。把它推迟到第一次真正用到时再编译，能明显缩短开机后
# 桌宠出现的时间。
$script:win32Ready = $false
function Initialize-Win32 {
    if ($script:win32Ready) { return }
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
    $script:win32Ready = $true
}

function Open-SyncFolder {
    Initialize-Win32
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
# 默认屏幕中央（实际位置在窗口创建后调整）
$pos = [pscustomobject]@{ Left = 960.0; Top = 540.0 }
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
# 不同形象的可见主体位置不同：pet.png 上下各有透明留白，阴影、状态点、气泡都贴着可见主体放。
if (Test-Path $petPng) {
    $shadowXaml   = 'VerticalAlignment="Top" Margin="0,69,0,0"'
    $dotXaml      = 'HorizontalAlignment="Left" VerticalAlignment="Top" Margin="74,54,0,0"'
    $bubbleOffset = 20
    $bodyXaml = @"
    <Image x:Name="Pet" Source="$([Uri]::new($petPng).AbsoluteUri)" Width="96" Height="96" Cursor="Hand"
           RenderTransformOrigin="0.5,0.5">
      <Image.RenderTransform>$transformBlock</Image.RenderTransform>
    </Image>
"@
} else {
    $shadowXaml   = 'VerticalAlignment="Bottom" Margin="0,0,0,-4"'
    $dotXaml      = 'HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,2,2"'
    $bubbleOffset = -4
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
        Title="OracleSyncPet" ToolTip="左键拖动 · 点击打开 Oracle-Sync · 右键菜单">
  <Window.Resources>
    <!-- 统一的深色圆角提示框（窗口提示与状态点提示共用） -->
    <Style TargetType="ToolTip">
      <Setter Property="HasDropShadow" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToolTip">
            <Border Background="#F0262B33" CornerRadius="7" Padding="10,6" Margin="8">
              <Border.Effect>
                <DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.3"/>
              </Border.Effect>
              <ContentPresenter TextBlock.Foreground="#FFF5F6F8" TextBlock.FontSize="12"
                                TextBlock.FontFamily="Microsoft YaHei UI, Segoe UI Emoji"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="8">
    <Ellipse x:Name="GroundShadow" Width="64" Height="12" HorizontalAlignment="Center"
             $shadowXaml IsHitTestVisible="False" RenderTransformOrigin="0.5,0.5">
      <Ellipse.Fill>
        <RadialGradientBrush>
          <GradientStop Color="#40000000" Offset="0"/>
          <GradientStop Color="#00000000" Offset="1"/>
        </RadialGradientBrush>
      </Ellipse.Fill>
      <Ellipse.RenderTransform><ScaleTransform x:Name="ShadowScale" ScaleX="1" ScaleY="1"/></Ellipse.RenderTransform>
    </Ellipse>
    $bodyXaml
    <Ellipse x:Name="StatusDot" Width="16" Height="16" $dotXaml
             Fill="#FF9E9E9E" Stroke="White" StrokeThickness="2.5"
             ToolTip="Syncthing 状态：检测中…">
      <Ellipse.Effect>
        <DropShadowEffect BlurRadius="5" ShadowDepth="1" Opacity="0.4"/>
      </Ellipse.Effect>
    </Ellipse>
    <Popup x:Name="Bubble" PlacementTarget="{Binding ElementName=Pet}" Placement="Top"
           AllowsTransparency="True" StaysOpen="True" VerticalOffset="$bubbleOffset" HorizontalOffset="0"
           PopupAnimation="Fade">
      <!-- 外层留白给阴影；气泡主体 + 底部小尾巴共用一个阴影 -->
      <StackPanel x:Name="BubbleRoot" Margin="12,10,12,6" Cursor="Hand">
        <StackPanel.Effect>
          <DropShadowEffect BlurRadius="12" ShadowDepth="2" Direction="270" Opacity="0.22"/>
        </StackPanel.Effect>
        <Border x:Name="BubbleBorder" Background="#FFFFFCF5" BorderBrush="#FFEBDDBA"
                BorderThickness="1" CornerRadius="14" Padding="14,9,14,8" MaxWidth="260" MinWidth="80">
          <StackPanel>
            <TextBlock x:Name="BubbleText" FontFamily="Microsoft YaHei UI, Segoe UI Emoji"
                       FontSize="13.5" Foreground="#FF3D3424" TextWrapping="Wrap" LineHeight="20"
                       Text="该喝水啦 💧"/>
            <TextBlock Text="点击收起" FontFamily="Microsoft YaHei UI" FontSize="10.5"
                       Foreground="#FFB3A57E" HorizontalAlignment="Right" Margin="0,3,0,0"/>
          </StackPanel>
        </Border>
        <Path Data="M0,0 L8,8 L16,0" Fill="#FFFFFCF5" Stroke="#FFEBDDBA" StrokeThickness="1"
              HorizontalAlignment="Center" Margin="0,-1,0,0"/>
      </StackPanel>
    </Popup>
  </Grid>
</Window>
"@

# 右键菜单：圆角卡片 + 图标列 + 悬停高亮，替换 WPF 默认的老式菜单外观。
# 图标用系统自带的 Segoe MDL2 Assets 字体，菜单项的 Icon 属性直接放字形字符。
$menuXaml = @"
<ContextMenu xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             HasDropShadow="False">
  <ContextMenu.Template>
    <ControlTemplate TargetType="ContextMenu">
      <Border Background="#FFFFFFFF" BorderBrush="#FFE4E6EB" BorderThickness="1"
              CornerRadius="10" Padding="0,5" Margin="10" MinWidth="200">
        <Border.Effect>
          <DropShadowEffect BlurRadius="16" ShadowDepth="3" Direction="270" Opacity="0.18"/>
        </Border.Effect>
        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
      </Border>
    </ControlTemplate>
  </ContextMenu.Template>
  <ContextMenu.Resources>
    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="#FF1F2329"/>
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Margin="5,1" Padding="10,7,16,7">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="26"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="Ico" Text="{Binding Icon, RelativeSource={RelativeSource TemplatedParent}}"
                           FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FF6B7280"
                           VerticalAlignment="Center"/>
                <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True"
                                  VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#FFF1F3F6"/>
                <Setter TargetName="Ico" Property="Foreground" Value="#FF3B82F6"/>
              </Trigger>
              <MultiTrigger>
                <MultiTrigger.Conditions>
                  <Condition Property="IsHighlighted" Value="True"/>
                  <Condition Property="Tag" Value="danger"/>
                </MultiTrigger.Conditions>
                <Setter TargetName="Bd" Property="Background" Value="#FFFDECEC"/>
                <Setter TargetName="Ico" Property="Foreground" Value="#FFE53935"/>
                <Setter Property="Foreground" Value="#FFD32F2F"/>
              </MultiTrigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="{x:Static MenuItem.SeparatorStyleKey}" TargetType="Separator">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Separator">
            <Border Height="1" Background="#FFECEEF1" Margin="12,4"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </ContextMenu.Resources>
</ContextMenu>
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
$bubbleRoot  = $win.FindName('BubbleRoot')
$shadowScale = $win.FindName('ShadowScale')

# Placement=Top 只对齐左边缘；按气泡实际宽度算偏移，让尾巴正对桌宠中线。
$bubbleRoot.Add_SizeChanged({
    $bubble.HorizontalOffset = ($pet.ActualWidth - $bubbleRoot.ActualWidth) / 2
})

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
$menu = [Windows.Markup.XamlReader]::Parse($menuXaml)
function New-MenuItem([string]$header, [int]$glyph) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    $mi.Icon   = [string][char]$glyph
    return $mi
}
$miOpen = New-MenuItem '打开 Oracle-Sync' 0xE838
$miOpen.Add_Click({ Open-SyncFolder })
$miReset = New-MenuItem '回到屏幕中央' 0xE81D
$miReset.Add_Click({
    $win.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth  - $win.ActualWidth)  / 2
    $win.Top  = ([System.Windows.SystemParameters]::PrimaryScreenHeight - $win.ActualHeight) / 2
    @{ Left = $win.Left; Top = $win.Top } | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
})
$miExit = New-MenuItem '退出桌宠' 0xE7E8
$miExit.Tag = 'danger'
$miExit.Add_Click({ $win.Close() })
$miWater = New-MenuItem '立即提醒喝水' 0xE916
$miSync  = New-MenuItem '查看同步状态' 0xE895
$miPause = New-MenuItem '暂停同步' 0xE769
$miWaterDone = New-MenuItem '已喝水，恢复显示' 0xE73E
$miWaterDone.IsEnabled = $false
[void]$menu.Items.Add($miOpen)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miSync)
[void]$menu.Items.Add($miPause)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miWater)
[void]$menu.Items.Add($miWaterDone)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miReset)
[void]$menu.Items.Add($miExit)
$win.ContextMenu = $menu

# ---------- 闲置时的呼吸动画 ----------
$breathe = New-Object System.Windows.Media.Animation.DoubleAnimation
$breathe.From = 1.0; $breathe.To = 1.06
$breathe.Duration = [System.Windows.Duration]([TimeSpan]::FromSeconds(2))
$breathe.AutoReverse = $true
$breathe.EasingFunction = New-Object System.Windows.Media.Animation.SineEase -Property @{ EasingMode = 'EaseInOut' }
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
    # 跳起时地面阴影同步缩小变淡
    $s = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.6, ([TimeSpan]::FromMilliseconds(220))
    $s.AutoReverse = $true
    $s.EasingFunction = $a.EasingFunction
    $shadowScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $s)
    $shadowScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $s)
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

# ---------- 通用通知气泡 ----------
$script:bubbleSource = $null
function Show-Bubble([string]$text, [int]$seconds = 0, [string]$source = 'notification') {
    $script:bubbleSource = $source
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

# ---------- 喝水滤镜：原生分层窗口，按物理像素覆盖每块显示器 ----------
# 不修改系统颜色设置；窗口透明且不激活，保留鼠标穿透。
function Initialize-WaterFilter {
    if ('OracleWaterFilter' -as [type]) { return }
    Add-Type @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class OracleWaterFilter {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WNDCLASS {
        public uint style; public IntPtr proc; public int clsExtra, wndExtra;
        public IntPtr instance, icon, cursor, background;
        public string menu, name;
    }
    delegate IntPtr WindowProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
    delegate bool MonitorProc(IntPtr monitor, IntPtr dc, ref RECT rect, IntPtr data);
    static readonly WindowProc proc = WndProc;
    static readonly List<IntPtr> windows = new List<IntPtr>();
    static List<RECT> bounds = new List<RECT>();
    static ushort atom;
    static IntPtr brush;
    const uint Styles = 0x00080000 | 0x00000020 | 0x08000000 | 0x00000080 | 0x00000008;
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern ushort RegisterClassW(ref WNDCLASS c);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateWindowExW(uint ex, string cls, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorProc callback, IntPtr data);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] public static extern int GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")] public static extern bool GetLayeredWindowAttributes(IntPtr h, out uint key, out byte alpha, out uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(uint color);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    static IntPtr WndProc(IntPtr h, uint msg, IntPtr w, IntPtr l) {
        if (msg == 0x0084) return new IntPtr(-1); // HTTRANSPARENT
        if (msg == 0x0021) return new IntPtr(3);  // MA_NOACTIVATE
        return DefWindowProcW(h, msg, w, l);
    }
    static List<RECT> Screens() {
        var result = new List<RECT>();
        if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
            delegate(IntPtr m, IntPtr dc, ref RECT r, IntPtr data) { result.Add(r); return true; }, IntPtr.Zero))
            throw new Win32Exception();
        return result;
    }
    public static IntPtr[] Handles { get { return windows.ToArray(); } }
    public static RECT[] MonitorBounds { get { return bounds.ToArray(); } }
    public static void Show() {
        IntPtr old = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            var screens = Screens();
            bool same = screens.Count == bounds.Count && windows.Count == screens.Count;
            for (int i=0; same && i<screens.Count; i++)
                same = screens[i].Equals(bounds[i]) && IsWindow(windows[i]);
            if (!same) {
                Hide();
                if (atom == 0) {
                    // COLORREF 0x00BBGGRR，对应 #409CFF。
                    brush = CreateSolidBrush(0x00FF9C40);
                    if (brush == IntPtr.Zero) throw new Win32Exception();
                    var c = new WNDCLASS { proc=Marshal.GetFunctionPointerForDelegate(proc),
                        instance=GetModuleHandleW(null), background=brush, name="OracleSyncWaterOverlay" };
                    atom = RegisterClassW(ref c);
                    if (atom == 0) throw new Win32Exception();
                }
                foreach (var r in screens) {
                    IntPtr h = CreateWindowExW(Styles, "OracleSyncWaterOverlay", "OracleSyncWaterFilter", 0x80000000,
                        r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top, IntPtr.Zero, IntPtr.Zero, GetModuleHandleW(null), IntPtr.Zero);
                    if (h == IntPtr.Zero) throw new Win32Exception();
                    windows.Add(h);
                    if (!SetLayeredWindowAttributes(h, 0, 51, 2)) throw new Win32Exception();
                }
                bounds = screens;
            }
            for (int i=0; i<windows.Count; i++) {
                var r = bounds[i];
                // HWND_TOPMOST + SWP_NOACTIVATE + SWP_SHOWWINDOW；坐标不经过 WPF 的 DIP 转换。
                if (!SetWindowPos(windows[i], new IntPtr(-1), r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top, 0x0050))
                    throw new Win32Exception();
            }
        } catch { Hide(); throw; }
        finally { if (old != IntPtr.Zero) SetThreadDpiAwarenessContext(old); }
    }
    public static void Hide() {
        foreach (IntPtr h in windows) DestroyWindow(h);
        windows.Clear(); bounds.Clear();
    }
}
"@
}

$script:waterActive = $false
$waterTimer = New-Object System.Windows.Threading.DispatcherTimer
$waterTimer.Interval = [TimeSpan]::FromMinutes(30)
$waterFilterTimer = New-Object System.Windows.Threading.DispatcherTimer
$waterFilterTimer.Interval = [TimeSpan]::FromSeconds(2)
$waterLog = Join-Path $stateDir 'water.log'
function Write-WaterLog([string]$event, [string]$msg = '') {
    try {
        $line = "{0}  {1}  {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $event, $msg
        Add-Content -Path $waterLog -Value $line -Encoding UTF8
    } catch {}
}
function Hide-WaterFilter([switch]$RestartTimer) {
    $waterFilterTimer.Stop()
    if ('OracleWaterFilter' -as [type]) { [OracleWaterFilter]::Hide() }
    $script:waterActive = $false
    $miWaterDone.IsEnabled = $false
    if ($RestartTimer) {
        $waterTimer.Stop()
        $waterTimer.Start()
        Write-WaterLog 'confirmed' '已恢复显示，30 分钟后再次提醒'
    }
}
function Show-WaterFilter([string]$source = 'manual') {
    try {
        Initialize-WaterFilter
        [OracleWaterFilter]::Show()
        $script:waterActive = $true
        $miWaterDone.IsEnabled = $true
        $waterTimer.Stop()
        $waterFilterTimer.Start()
        Write-WaterLog $source ("淡蓝滤镜开启，屏幕数：" + [OracleWaterFilter]::Handles.Length)
    } catch {
        Hide-WaterFilter
        Write-WaterLog 'error' $_.Exception.Message
        $waterTimer.Stop()
        $waterTimer.Start()
    }
}
$waterFilterTimer.Add_Tick({
    if (-not $script:waterActive) { return }
    try { [OracleWaterFilter]::Show() } catch {
        Write-WaterLog 'error' $_.Exception.Message
        Hide-WaterFilter -RestartTimer
    }
})
$waterTimer.Add_Tick({ Show-WaterFilter 'fire' })
$waterTimer.Start()
$miWater.Add_Click({ Show-WaterFilter 'manual' })
$miWaterDone.Add_Click({ Hide-WaterFilter -RestartTimer })

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
$colorWarn    = '#FFFF9800'  # 橙：本机无待同步项，但未连接到同步设备
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

# ---- 后台轮询：网络 I/O 放到独立 runspace，绝不阻塞 UI 线程 ----
# 旧版在 UI 线程上同步调用 REST：开机时 Syncthing 正忙着做自己的启动扫描、响应很慢，
# 三个请求最坏要等 6 秒，期间桌宠窗口卡住出不来——这就是"开机扫描很慢"的根因。
# 现在改成后台线程拉数据，主线程只在 Tick 时收割结果刷新小圆点，彻底消除卡顿。
$script:syncLast   = @{ kind = 'unknown'; tip = '检测中…' }
$script:pollPS     = $null
$script:pollHandle = $null

# 纯网络逻辑，运行在后台 runspace 里。绝不能碰任何 WPF 对象，只返回原始数据哈希表。
$pollScript = {
    param($apiKey, $folderId)
    function Test-Port {
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect('127.0.0.1', 8384, $null, $null)
            $ok = $ar.AsyncWaitHandle.WaitOne(300)
            if ($ok -and $c.Connected) { $c.EndConnect($ar); $c.Close(); return $true }
            $c.Close(); return $false
        } catch { return $false }
    }
    if (-not $apiKey -or -not $folderId) { return @{ kind = 'unknown'; tip = '未找到 Syncthing 配置' } }
    if (-not (Test-Port))                { return @{ kind = 'offline'; tip = 'Syncthing 未运行（127.0.0.1:8384 无响应）' } }
    $headers = @{ 'X-API-Key' = $apiKey }
    try {
        $fcfg = Invoke-RestMethod -Uri "http://127.0.0.1:8384/rest/config/folders/$folderId" -Headers $headers -TimeoutSec 2
    } catch { return @{ kind = 'error'; tip = ('Syncthing 无响应：' + $_.Exception.Message) } }
    if ($fcfg.paused) { return @{ kind = 'paused'; tip = '已暂停同步（右键 → 暂停 / 恢复同步 可恢复）' } }
    try {
        $st = Invoke-RestMethod -Uri "http://127.0.0.1:8384/rest/db/status?folder=$folderId" -Headers $headers -TimeoutSec 2
        $cn = Invoke-RestMethod -Uri 'http://127.0.0.1:8384/rest/system/connections' -Headers $headers -TimeoutSec 2
    } catch { return @{ kind = 'error'; tip = ('Syncthing 无响应：' + $_.Exception.Message) } }
    $connected = 0
    if ($cn.connections) {
        foreach ($p in $cn.connections.PSObject.Properties) { if ($p.Value.connected) { $connected++ } }
    }
    return @{
        state     = [string]$st.state
        needBytes = [long]$st.needBytes
        needFiles = [int]($st.needFiles + $st.needDirectories + $st.needSymlinks + $st.needDeletes)
        connected = $connected
        error     = [string]$st.error
    }
}

# 把后台返回的原始数据翻译成 kind + tip（运行在 UI 线程）。
function Resolve-SyncKind($r) {
    if ($r.ContainsKey('kind')) { return $r }   # 已是终态：unknown / offline / paused / error
    $needB = [long]$r.needBytes; $needF = [int]$r.needFiles; $state = [string]$r.state
    if ($state -eq 'syncing' -or $state -eq 'scanning') {
        $label = if ($state -eq 'scanning') { '扫描中' } else { '同步中' }
        $tip = if ($needB -gt 0 -or $needF -gt 0) { "$label · 剩 $(Get-HumanBytes $needB) / $needF 项" } else { "$label…" }
        return @{ kind = 'sync'; tip = $tip }
    } elseif ($state -eq 'error') {
        return @{ kind = 'error'; tip = "同步出错：$($r.error)" }
    } elseif ($needB -gt 0 -or $needF -gt 0) {
        return @{ kind = 'sync'; tip = "等待同步 · 剩 $(Get-HumanBytes $needB) / $needF 项" }
    } elseif ([int]$r.connected -gt 0) {
        return @{ kind = 'ok'; tip = "已同步 · 与 $($r.connected) 台设备相连" }
    } else {
        return @{ kind = 'warn'; tip = '本机无待同步项 · 未连接到同步设备' }
    }
}

# 拿到一次轮询结果后刷新小圆点，并在状态变化时弹气泡（运行在 UI 线程）。
function Apply-SyncResult($raw) {
    $res = Resolve-SyncKind $raw
    $k = $res.kind
    Set-StatusDot $k $res.tip
    $prev = $script:syncLastKind
    if ($prev -and $prev -ne $k) {
        switch ("$prev->$k") {
            'ok->sync'      { Show-Bubble '🔄 开始同步…' -source 'sync' }
            'warn->sync'    { Show-Bubble '🔄 开始同步…' -source 'sync' }
            'unknown->sync' { }
            'sync->ok'      { Show-Bubble '✅ Oracle-Sync 同步完成' -source 'sync' }
            'sync->warn'    { Show-Bubble '本机无待同步项 · 未连接到同步设备' -source 'sync' }
            'ok->offline'   { Show-Bubble '⚠️ Syncthing 不在跑了' -source 'sync' }
            'sync->offline' { Show-Bubble '⚠️ Syncthing 不在跑了' -source 'sync' }
            'ok->error'     { Show-Bubble '⚠️ 同步出错，看下小圆点' -source 'sync' }
            'sync->error'   { Show-Bubble '⚠️ 同步出错，看下小圆点' -source 'sync' }
            'paused->ok'    { Show-Bubble '▶ 已恢复同步' -source 'sync' }
            'paused->sync'  { Show-Bubble '▶ 已恢复同步' -source 'sync' }
            'paused->warn'  { Show-Bubble '本机无待同步项 · 未连接到同步设备' -source 'sync' }
        }
    }
    $script:syncLastKind = $k
    $script:syncLast = $res
    # 同步气泡持续展示当前状态；只改文字，不重新打开、不反复蹦跳。
    # 外部任务通知使用独立来源，轮询不得覆盖用户尚未读完的通知。
    if ($bubble.IsOpen -and $script:bubbleSource -eq 'sync') {
        $bubbleText.Text = $res.tip
    }
}

# 每个 Tick：先收割上一次后台轮询的结果（若已完成），再视情况启动下一次。
# UI 线程在这里绝不等待网络——只看 IsCompleted，没好就下次再来。
function Pump-SyncPoll {
    if ($script:pollHandle -and $script:pollHandle.IsCompleted) {
        try {
            $out = $script:pollPS.EndInvoke($script:pollHandle)
            $raw = $out | Select-Object -Last 1
            if ($raw) { Apply-SyncResult $raw }
        } catch { try { Set-StatusDot 'unknown' ('状态轮询异常：' + $_.Exception.Message) } catch {} }
        finally {
            try { $script:pollPS.Dispose() } catch {}
            $script:pollPS = $null; $script:pollHandle = $null
        }
    }
    if (-not $script:pollHandle) {
        try {
            $script:pollPS = [PowerShell]::Create()
            [void]$script:pollPS.AddScript($pollScript).AddArgument($script:syncApiKey).AddArgument($script:syncFolderId)
            $script:pollHandle = $script:pollPS.BeginInvoke()
        } catch { $script:pollPS = $null; $script:pollHandle = $null }
    }
}

$syncTimer = New-Object System.Windows.Threading.DispatcherTimer
$syncTimer.Interval = [TimeSpan]::FromSeconds(3)
$syncTimer.Add_Tick({
    # 单次 Tick 异常不能让 DispatcherTimer 静默停掉——否则状态就永远卡在上一次值。
    try { Pump-SyncPoll }
    catch { try { Set-StatusDot 'unknown' ("状态轮询异常：" + $_.Exception.Message) } catch {} }
})

# ---------- 强制置顶：定时把桌宠顶回最上层 ----------
# XAML 的 Topmost=True 只在"出生时"把窗口放进置顶层。之后前台争夺、其它置顶程序、
# 分辨率/显示器变化、锁屏解锁等会把它挤出置顶层——即便 WPF 的 Topmost 属性仍是 True，
# 窗口实际的 WS_EX_TOPMOST 位也可能被系统清掉（已实测复现），桌宠就被别的窗口盖住，
# 这就是"有时候不会置顶"的根因。
# 修复：把 WPF 的 Topmost 走一遍 false→true，强制 WPF 重新申请置顶（已实测能把被挤掉的
# 窗口顶回去）。不直接用 SetWindowPos——WPF 的窗口过程会按自己的 Topmost 属性纠正外部
# 的 Z 序改动，实测 SetWindowPos 单独调用不生效。纯属性切换零编译开销，不拖慢开机。
function Set-AlwaysOnTop {
    # 拖动中 / 气泡或右键菜单开着时不切换：切 Topmost 会瞬间打断这些 Popup（右键菜单还会被关掉）。
    if ($win.IsMouseCaptured -or $bubble.IsOpen -or $menu.IsOpen) { return }
    $win.Topmost = $false
    $win.Topmost = $true
}
$topmostTimer = New-Object System.Windows.Threading.DispatcherTimer
$topmostTimer.Interval = [TimeSpan]::FromSeconds(2)
$topmostTimer.Add_Tick({ try { Set-AlwaysOnTop } catch {} })
# 桌宠一旦失去前台（多半是别的窗口冒到前面），立刻顶回去，恢复更跟手。
$win.Add_Deactivated({ try { Set-AlwaysOnTop } catch {} })

# 窗口内容渲染完成后再启动轮询：先让桌宠瞬间出现，不被网络请求拖住开机。
$win.Add_ContentRendered({
    try { Pump-SyncPoll } catch {}   # 立刻发起第一次轮询（后台线程，不阻塞）
    $syncTimer.Start()
    $topmostTimer.Start()
    if ($WaterPreview) { Show-WaterFilter 'preview' }
})

# 右键菜单"查看同步状态"——显示最近一次后台轮询的缓存结果，并顺手触发一次刷新
$miSync.Add_Click({
    if ($script:syncLast -and $script:syncLast.tip) { Show-Bubble $script:syncLast.tip -source 'sync' }
    else { Show-Bubble 'Syncthing 状态：检测中…' -source 'sync' }
    try { Pump-SyncPoll } catch {}
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
        try { Pump-SyncPoll } catch {}
    } catch {
        Show-Bubble ("切换失败：" + $_.Exception.Message)
    }
})

# 打开菜单前刷新"暂停 / 恢复"标签
$menu.Add_Opened({
    if ($script:syncLastKind -eq 'paused') { $miPause.Header = '恢复同步'; $miPause.Icon = [string][char]0xE768 }
    else                                    { $miPause.Header = '暂停同步'; $miPause.Icon = [string][char]0xE769 }
})

# 单实例：互斥锁
$mutex = New-Object System.Threading.Mutex($false, 'Global\OracleSyncPet')
if (-not $mutex.WaitOne(0)) { Write-ExitLog 'mutex busy, exit'; return }

# 窗口关闭与未处理异常的记录（只记录，不改变异常是否终止进程的行为）
$win.Add_Closed({ Write-ExitLog 'window closed' })
$win.Dispatcher.add_UnhandledException({ param($s, $e) Write-ExitLog ('unhandled: ' + $e.Exception.ToString()) })

try {
    [void]$win.ShowDialog()
} finally {
    Write-ExitLog 'finally reached'
    Hide-WaterFilter
    foreach ($t in @($waterTimer, $waterFilterTimer, $timer, $notifyPoll, $syncTimer, $topmostTimer)) {
        if ($t) { $t.Stop() }
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
