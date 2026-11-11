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

# 单实例：互斥锁。放在最前面，已有桌宠在跑时立刻退出，不再白白创建窗口和计时器。
$mutex = New-Object System.Threading.Mutex($false, 'Global\OracleSyncPet')
if (-not $mutex.WaitOne(0)) { Write-ExitLog 'mutex busy, exit'; return }
[AppDomain]::CurrentDomain.add_ProcessExit({ Write-ExitLog 'process exit (normal)' })

# ---------- 打开/激活同步文件夹（与 open-sync-folder.ps1 共用） ----------
. (Join-Path $PSScriptRoot 'oracle-sync-common.ps1')
function Open-SyncFolder { Open-OracleSyncFolder $root }

# ---------- 加载位置 ----------
# 默认屏幕中央（实际位置在窗口创建后调整）
$pos = [pscustomobject]@{ Left = 960.0; Top = 540.0 }
if (Test-Path $stateFile) {
    try { $pos = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

# region UI-XAML（preview-ui.ps1 会截取 region 到 endregion 之间的代码离屏渲染，改动时保持自包含）
# ---------- 皮肤配置列表（共 5 款皮肤） ----------
$skinDefs = @(
    # Dot：同步状态圆点左上角位置（96×96 形象框内）。横图皮肤放在右下角牌子外侧，避免挡住文字。
    [pscustomobject]@{ Id = 'default';     Name = '默认形象';   File = 'pet.png';          Dot = '74,54,0,0' },
    [pscustomobject]@{ Id = 'tgood_board'; Name = '特锐德牌子'; File = '特锐德牌子.png';   Dot = '80,64,0,0' },
    [pscustomobject]@{ Id = 'tgood_robot'; Name = '特锐德机器人'; File = '特锐德机器人.png'; Dot = '80,64,0,0' },
    [pscustomobject]@{ Id = 'teld_robot';  Name = '特来电机器人'; File = '特来电机器人.png'; Dot = '80,64,0,0' },
    [pscustomobject]@{ Id = 'teld_board';  Name = '特来电牌子'; File = '特来电牌子.png';   Dot = '80,64,0,0' }
)
$script:currentSkinId = if ($pos -and $pos.PSObject.Properties['Skin'] -and $pos.Skin) { [string]$pos.Skin } else { 'default' }
$currentSkinDef = $skinDefs | Where-Object { $_.Id -eq $script:currentSkinId } | Select-Object -First 1
if (-not $currentSkinDef) { $currentSkinDef = $skinDefs[0]; $script:currentSkinId = $currentSkinDef.Id }
$skinBaseDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($petPng) { Split-Path -Parent $petPng } else { (Get-Location).Path }
$currentSkinFile = Join-Path $skinBaseDir $currentSkinDef.File

# ---------- 桌宠大小（整体缩放倍数，存 state.json 的 Scale 字段） ----------
$sizeMin = 0.5; $sizeMax = 3.0
$script:petSize = 1.0
if ($pos -and $pos.PSObject.Properties['Scale'] -and $pos.Scale) {
    try { $script:petSize = [Math]::Min($sizeMax, [Math]::Max($sizeMin, [double]$pos.Scale)) } catch {}
}
$sizeXaml = ([string]$script:petSize).Replace(',', '.')

# ---------- 选择形象：优先皮肤图片，否则 emoji ----------
$transformBlock = @"
      <TransformGroup>
        <ScaleTransform     x:Name="PetScale"   ScaleX="1" ScaleY="1"/>
        <ScaleTransform     x:Name="ActScale"   ScaleX="1" ScaleY="1"/>
        <RotateTransform    x:Name="PetRotate"  Angle="0"/>
        <TranslateTransform x:Name="PetTrans"   X="0" Y="0"/>
      </TransformGroup>
"@
# 不同形象的可见主体位置不同：图片上下各有留白，阴影、状态点、气泡都贴着可见主体放。
if (Test-Path $currentSkinFile) {
    $shadowXaml   = 'VerticalAlignment="Top" Margin="0,69,0,0"'
    $dotXaml      = 'HorizontalAlignment="Left" VerticalAlignment="Top" Margin="{0}"' -f $currentSkinDef.Dot
    $bubbleOffset = 20
    $bodyXaml = @"
    <Image x:Name="Pet" Source="$([Uri]::new($currentSkinFile).AbsoluteUri)" Width="96" Height="96" Cursor="Hand"
           Stretch="Uniform" RenderTransformOrigin="0.5,0.5">
      <Image.RenderTransform>$transformBlock</Image.RenderTransform>
    </Image>
"@
} elseif ($petPng -and (Test-Path $petPng)) {
    $shadowXaml   = 'VerticalAlignment="Top" Margin="0,69,0,0"'
    $dotXaml      = 'HorizontalAlignment="Left" VerticalAlignment="Top" Margin="74,54,0,0"'
    $bubbleOffset = 20
    $bodyXaml = @"
    <Image x:Name="Pet" Source="$([Uri]::new($petPng).AbsoluteUri)" Width="96" Height="96" Cursor="Hand"
           Stretch="Uniform" RenderTransformOrigin="0.5,0.5">
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
        Title="OracleSyncPet" ToolTip="左键拖动 · 右键菜单">
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
    <Grid.LayoutTransform><ScaleTransform x:Name="SizeScale" ScaleX="$sizeXaml" ScaleY="$sizeXaml"/></Grid.LayoutTransform>
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
             Fill="#FF9E9E9E" Stroke="White" StrokeThickness="2.5" Cursor="Hand"
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
            <TextBlock x:Name="BubbleHint" Text="点击收起" FontFamily="Microsoft YaHei UI" FontSize="10.5"
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
                  <ColumnDefinition Width="16"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="Ico" Text="{Binding Icon, RelativeSource={RelativeSource TemplatedParent}}"
                           FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FF6B7280"
                           VerticalAlignment="Center"/>
                <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True"
                                  VerticalAlignment="Center"/>
                <TextBlock Grid.Column="2" x:Name="Arrow" Text="&#xE76C;" FontFamily="Segoe MDL2 Assets"
                           FontSize="10" Foreground="#FF9CA3AF" VerticalAlignment="Center" Visibility="Collapsed"/>
                <Popup x:Name="PART_Popup" AllowsTransparency="True" Focusable="False"
                       IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}"
                       Placement="Right" HorizontalOffset="-4" VerticalOffset="-5">
                  <Border Background="#FFFFFFFF" BorderBrush="#FFE4E6EB" BorderThickness="1"
                          CornerRadius="10" Padding="0,5" Margin="10" MinWidth="160">
                    <Border.Effect>
                      <DropShadowEffect BlurRadius="16" ShadowDepth="3" Direction="270" Opacity="0.18"/>
                    </Border.Effect>
                    <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                  </Border>
                </Popup>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="HasItems" Value="True">
                <Setter TargetName="Arrow" Property="Visibility" Value="Visible"/>
              </Trigger>
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
              <!-- 顶部的状态信息行：只展示，不可点击 -->
              <Trigger Property="Tag" Value="info">
                <Setter TargetName="Bd" Property="Background" Value="#FFF7F8FA"/>
                <Setter TargetName="Ico" Property="Foreground" Value="#FF9CA3AF"/>
                <Setter Property="Foreground" Value="#FF6B7280"/>
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="IsHitTestVisible" Value="False"/>
                <Setter Property="Focusable" Value="False"/>
              </Trigger>
              <Trigger Property="Tag" Value="alert">
                <Setter TargetName="Ico" Property="Foreground" Value="#FFE53935"/>
                <Setter Property="Foreground" Value="#FFD32F2F"/>
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

# endregion UI-XAML

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
$bubbleHint  = $win.FindName('BubbleHint')
$statusDot   = $win.FindName('StatusDot')
$bubbleRoot  = $win.FindName('BubbleRoot')
$shadowScale = $win.FindName('ShadowScale')

# Placement=Top 只对齐左边缘；按气泡实际宽度算偏移，让尾巴正对桌宠中线。
$bubbleRoot.Add_SizeChanged({
    $bubble.HorizontalOffset = ($pet.ActualWidth - $bubbleRoot.ActualWidth) / 2
})

# ---------- 屏幕范围、位置校正与贴边 ----------
# 屏幕坐标统一换算成 WPF 的 DIP（与 $win.Left/Top 同一套单位）。
Add-Type -AssemblyName System.Windows.Forms
$script:dock      = $null    # 'left' / 'right' / $null：贴在哪一侧屏幕边缘
$script:dockShown = $false   # 贴边时当前是否完整探出
if ($pos.PSObject.Properties['Dock'] -and $pos.Dock) { $script:dock = [string]$pos.Dock }

function Save-PetState {
    $left = $win.Left
    if ($script:dock) { $left = Get-DockX $script:dock $false }   # 贴边时总是记录"藏起来"的位置
    @{ Left = $left; Top = $win.Top; Dock = $script:dock; Skin = $script:currentSkinId; Scale = $script:petSize } | ConvertTo-Json |
        Set-Content -Path $stateFile -Encoding UTF8
}

function Get-PetScreens {
    $m = [System.Windows.Media.Matrix]::Identity
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    if ($src) { $m = $src.CompositionTarget.TransformToDevice }
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $b = $s.Bounds; $w = $s.WorkingArea
        [pscustomobject]@{
            Bounds = [System.Windows.Rect]::new($b.X / $m.M11, $b.Y / $m.M22, $b.Width / $m.M11, $b.Height / $m.M22)
            Work   = [System.Windows.Rect]::new($w.X / $m.M11, $w.Y / $m.M22, $w.Width / $m.M11, $w.Height / $m.M22)
        }
    }
}
function Get-PetRect { [System.Windows.Rect]::new($win.Left, $win.Top, $win.ActualWidth, $win.ActualHeight) }

# 与桌宠重叠面积最大的那块屏幕；完全不重叠时返回 $null
function Get-PetScreen {
    $r = Get-PetRect; $best = $null; $bestArea = 0
    foreach ($s in Get-PetScreens) {
        $i = [System.Windows.Rect]::Intersect($s.Bounds, $r)
        if (-not $i.IsEmpty -and $i.Width * $i.Height -gt $bestArea) { $best = $s; $bestArea = $i.Width * $i.Height }
    }
    return $best
}

# 拔掉显示器、换分辨率后桌宠可能落在看不见的地方：可见部分太少就拉回主屏右下角。
function Ensure-OnScreen {
    if ($win.IsMouseCaptured -or $slideTimer.IsEnabled) { return }
    $r = Get-PetRect
    foreach ($s in Get-PetScreens) {
        $i = [System.Windows.Rect]::Intersect($s.Bounds, $r)
        if (-not $i.IsEmpty -and $i.Width -ge 24 -and $i.Height -ge 24) { return }
    }
    $wa = [System.Windows.SystemParameters]::WorkArea
    $script:dock = $null
    $win.Left = $wa.Right  - $win.ActualWidth  - 40
    $win.Top  = $wa.Bottom - $win.ActualHeight - 40
    Save-PetState
}

# 贴边位置：藏起来时只露出约 45%，探出时完整贴着屏幕边
function Get-DockX([string]$side, [bool]$shown) {
    $s = Get-PetScreen
    $b = if ($s) { $s.Bounds } else { [System.Windows.Rect]::new(0, 0, [System.Windows.SystemParameters]::PrimaryScreenWidth, [System.Windows.SystemParameters]::PrimaryScreenHeight) }
    $w = $win.ActualWidth
    if ($side -eq 'left') { if ($shown) { return $b.Left } else { return $b.Left - $w * 0.55 } }
    if ($shown) { return $b.Right - $w } else { return $b.Right - $w * 0.45 }
}

# 松手时离屏幕左/右外侧边缘足够近就贴边；两块屏幕相接的内侧边不算。
function Get-SnapSide {
    $s = Get-PetScreen
    if (-not $s) { return $null }
    $r = Get-PetRect; $cy = $r.Top + $r.Height / 2
    $outside = {
        param($x)
        foreach ($o in Get-PetScreens) { if ($o.Bounds.Contains([System.Windows.Point]::new($x, $cy))) { return $false } }
        return $true
    }
    if ($r.Left  -le $s.Bounds.Left  + 24 -and (& $outside ($s.Bounds.Left  - 4))) { return 'left' }
    if ($r.Right -ge $s.Bounds.Right - 24 -and (& $outside ($s.Bounds.Right + 4))) { return 'right' }
    return $null
}

# 水平滑动的小补间动画（Window.Left 不适合直接挂 WPF 动画，拖动时会被动画锁住）
$script:slideTarget = 0.0
$slideTimer = New-Object System.Windows.Threading.DispatcherTimer
$slideTimer.Interval = [TimeSpan]::FromMilliseconds(15)
$slideTimer.Add_Tick({
    $d = $script:slideTarget - $win.Left
    if ([Math]::Abs($d) -lt 1) { $win.Left = $script:slideTarget; $slideTimer.Stop(); return }
    $win.Left = $win.Left + $d * 0.3
})
function Slide-To([double]$x) { $script:slideTarget = $x; $slideTimer.Start() }

function Show-Docked {
    if (-not $script:dock) { return }
    $dockHideTimer.Stop()
    $script:dockShown = $true
    Slide-To (Get-DockX $script:dock $true)
}
function Hide-Docked {
    if (-not $script:dock) { return }
    if ($win.IsMouseOver -or $win.IsMouseCaptured -or $bubble.IsOpen -or $menu.IsOpen) { return }
    $script:dockShown = $false
    Slide-To (Get-DockX $script:dock $false)
}
# 鼠标离开 1.2 秒后再缩回去，避免擦边划过时来回抖动
$dockHideTimer = New-Object System.Windows.Threading.DispatcherTimer
$dockHideTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
$dockHideTimer.Add_Tick({ $dockHideTimer.Stop(); Hide-Docked })
function Request-HideDocked { if ($script:dock) { $dockHideTimer.Stop(); $dockHideTimer.Start() } }
$win.Add_MouseEnter({ Show-Docked })
$win.Add_MouseLeave({ Request-HideDocked })

# ---------- 拖动 vs 点击 ----------
$script:startMouse = $null
$script:startLeft  = 0.0
$script:startTop   = 0.0
$script:moved      = $false
$script:downOnDot  = $false

$win.Add_MouseLeftButtonDown({
    $script:startMouse = $win.PointToScreen($_.GetPosition($win))
    $script:startLeft  = $win.Left
    $script:startTop   = $win.Top
    $script:moved      = $false
    $script:downOnDot  = ($_.OriginalSource -eq $statusDot)
    $slideTimer.Stop()
    [void]$win.CaptureMouse()
})

$win.Add_MouseMove({
    if ($win.IsMouseCaptured) {
        # PointToScreen 返回物理像素，换算成 DIP 再加到 Left/Top 上
        $cur = $win.PointToScreen($_.GetPosition($win))
        $m = [System.Windows.PresentationSource]::FromVisual($win).CompositionTarget.TransformToDevice
        $dx  = ($cur.X - $script:startMouse.X) / $m.M11
        $dy  = ($cur.Y - $script:startMouse.Y) / $m.M22
        if ([Math]::Abs($dx) -gt 4 -or [Math]::Abs($dy) -gt 4) { $script:moved = $true; $script:dock = $null }
        if ($script:moved) {
            $win.Left = $script:startLeft + $dx
            $win.Top  = $script:startTop  + $dy
        }
    }
})

$win.Add_MouseLeftButtonUp({
    if ($win.IsMouseCaptured) { $win.ReleaseMouseCapture() }
    if ($script:moved) {
        $side = Get-SnapSide
        if ($side) {
            $script:dock = $side
            $script:dockShown = $true
            Slide-To (Get-DockX $side $true)
            Request-HideDocked
        }
        Save-PetState
    } elseif ($script:downOnDot) {
        # 点状态小圆点：打开 Syncthing 网页管理界面
        Start-Process 'http://127.0.0.1:8384/'
    } else {
        # 按一下：缩放动画
        $pop = New-Object System.Windows.Media.Animation.DoubleAnimation 0.75, 1.0, ([TimeSpan]::FromMilliseconds(220))
        $pop.EasingFunction = New-Object System.Windows.Media.Animation.BackEase -Property @{ Amplitude = 1.5; EasingMode = 'EaseOut' }
        $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pop)
        $actScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
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
# region UI-MENU（preview-ui.ps1 同样会截取这一段）
$menu = [Windows.Markup.XamlReader]::Parse($menuXaml)
function New-MenuItem([string]$header, [int]$glyph) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    $mi.Icon   = [string][char]$glyph
    return $mi
}
$miInfo = New-MenuItem 'Syncthing 状态：检测中…' 0xE946
$miInfo.Tag = 'info'
$miOpen = New-MenuItem '打开 Oracle-Sync' 0xE838
$miOpen.Add_Click({ Open-SyncFolder })
$miWeb = New-MenuItem '打开 Syncthing 管理页' 0xE774
$miWeb.Add_Click({ Start-Process 'http://127.0.0.1:8384/' })
$miReset = New-MenuItem '回到屏幕中央' 0xE81D
$miReset.Add_Click({
    $script:dock = $null
    $win.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth  - $win.ActualWidth)  / 2
    $win.Top  = ([System.Windows.SystemParameters]::PrimaryScreenHeight - $win.ActualHeight) / 2
    Save-PetState
})
$miExit = New-MenuItem '退出桌宠' 0xE7E8
$miExit.Tag = 'danger'
$miExit.Add_Click({ $win.Close() })
$miWater = New-MenuItem '立即提醒喝水' 0xE916
$miSync  = New-MenuItem '查看同步状态' 0xE895
$miPause = New-MenuItem '暂停同步' 0xE769
$miConflict = New-MenuItem '同步冲突文件' 0xE7BA
$miConflict.Tag = 'alert'
$miConflict.Visibility = 'Collapsed'
$miWaterDone = New-MenuItem '已喝水，恢复显示' 0xE73E
$miWaterDone.IsEnabled = $false
$miSnooze = New-MenuItem '5 分钟后再提醒' 0xE823
$miSnooze.IsEnabled = $false
$miDnd = New-MenuItem '勿扰 1 小时' 0xE708

# ---------- 切换皮肤菜单项与子项 ----------
$miSkin = New-MenuItem '切换皮肤' 0xE790
$script:skinMenuItems = @{}
foreach ($s in $skinDefs) {
    $subMi = New-Object System.Windows.Controls.MenuItem
    $subMi.Header = $s.Name
    $subMi.Tag    = $s.Id
    $subMi.Add_Click({
        param($sender, $e)
        Set-PetSkin $sender.Tag
    })
    $script:skinMenuItems[$s.Id] = $subMi
    [void]$miSkin.Items.Add($subMi)
}
function Update-SkinMenu {
    if (-not $script:skinMenuItems) { return }
    foreach ($id in $script:skinMenuItems.Keys) {
        $item = $script:skinMenuItems[$id]
        if ($id -eq $script:currentSkinId) {
            $item.Icon = [string][char]0xE73E
        } else {
            $item.Icon = ''
        }
    }
}
Update-SkinMenu

# ---------- 调节大小菜单项与子项 ----------
$miSize = New-MenuItem '调节大小' 0xE740
$script:sizeMenuItems = @{}
foreach ($p in @(@('小', 0.75), @('标准', 1.0), @('大', 1.25), @('特大', 1.5), @('超大', 2.0))) {
    $subMi = New-Object System.Windows.Controls.MenuItem
    $subMi.Header = '{0}（{1}%）' -f $p[0], [int]($p[1] * 100)
    $subMi.Tag    = [double]$p[1]
    $subMi.Add_Click({ param($sender, $e) Set-PetSize ([double]$sender.Tag) })
    $script:sizeMenuItems[[double]$p[1]] = $subMi
    [void]$miSize.Items.Add($subMi)
}
$miSizeHint = New-Object System.Windows.Controls.MenuItem
$miSizeHint.Header = '按住 Ctrl 滚动滚轮可微调'
$miSizeHint.IsEnabled = $false
[void]$miSize.Items.Add($miSizeHint)
function Update-SizeMenu {
    if (-not $script:sizeMenuItems) { return }
    foreach ($k in $script:sizeMenuItems.Keys) {
        $script:sizeMenuItems[$k].Icon = if ([Math]::Abs($k - $script:petSize) -lt 0.001) { [string][char]0xE73E } else { '' }
    }
    $miSize.Header = '调节大小（当前 {0}%）' -f [int][Math]::Round($script:petSize * 100)
}
Update-SizeMenu

foreach ($it in @(
    $miInfo, 'sep',
    $miOpen, $miWeb, 'sep',
    $miSync, $miPause, $miConflict, 'sep',
    $miSkin, $miSize, 'sep',
    $miWater, $miWaterDone, $miSnooze, $miDnd, 'sep',
    $miReset, $miExit)) {
    if ($it -is [string]) { [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator)) }
    else { [void]$menu.Items.Add($it) }
}
# endregion UI-MENU

# ---------- 动态切换皮肤 ----------
function Set-PetSkin([string]$skinId) {
    $def = $skinDefs | Where-Object { $_.Id -eq $skinId } | Select-Object -First 1
    if (-not $def) { return }
    $baseDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($petPng) { Split-Path -Parent $petPng } else { (Get-Location).Path }
    $path = Join-Path $baseDir $def.File
    if (-not (Test-Path $path)) {
        Show-Bubble "找不到皮肤文件：$($def.File)" -source 'manual'
        return
    }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = [Uri]::new($path)
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $bmp.Freeze()
        $pet.Source = $bmp
        if ($def.Dot) { $m = [double[]]($def.Dot -split ','); $statusDot.Margin = New-Object System.Windows.Thickness($m[0], $m[1], $m[2], $m[3]) }
        $script:currentSkinId = $skinId
        Save-PetState
        Update-SkinMenu
        Show-Bubble "已切换皮肤：$($def.Name)" -source 'manual'
    } catch {
        Show-Bubble "切换皮肤失败：$($_.Exception.Message)" -source 'manual'
    }
}
$win.ContextMenu = $menu

# ---------- 调节大小 ----------
# 整体缩放 Grid 的 LayoutTransform，SizeToContent 让窗口跟着变大变小；以脚底中点为锚点，
# 改大小时桌宠"站"在原地不跳位。贴边状态下重新按新宽度计算贴边位置。
$sizeScale = $win.FindName('SizeScale')
function Set-PetSize([double]$size) {
    $size = [Math]::Round([Math]::Min($sizeMax, [Math]::Max($sizeMin, $size)), 2)
    if ([Math]::Abs($size - $script:petSize) -lt 0.001) { return }
    $cx = $win.Left + $win.ActualWidth / 2
    $bottom = $win.Top + $win.ActualHeight
    $script:petSize = $size
    $sizeScale.ScaleX = $size; $sizeScale.ScaleY = $size
    $win.UpdateLayout()
    if ($script:dock) { $win.Left = Get-DockX $script:dock $script:dockShown }
    else { $win.Left = $cx - $win.ActualWidth / 2 }
    $win.Top = $bottom - $win.ActualHeight
    Update-SizeMenu
    Save-PetState
}
# Ctrl + 滚轮：每格 10%
$win.Add_PreviewMouseWheel({
    param($s, $e)
    if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -eq 0) { return }
    $step = if ($e.Delta -gt 0) { 0.1 } else { -0.1 }
    try { Set-PetSize ($script:petSize + $step) } catch {}
    $e.Handled = $true
})

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
# source 决定气泡的"分量"：
#   notification / conflict —— 需要用户看到的消息：不会被别的消息顶掉，排队依次显示；勿扰期间攒着，结束后再弹
#   sync                    —— 同步状态播报：只反映当前状态，被挡住或勿扰时直接丢弃（状态点仍会更新）
#   manual                  —— 用户刚在菜单里点的操作反馈：总是立即显示，原来未读的消息放回队首
$script:bubbleSource = $null
$script:bubbleQueue  = New-Object System.Collections.Generic.List[object]
$script:dndUntil     = [DateTime]::MinValue
function Test-Dnd { return [DateTime]::Now -lt $script:dndUntil }
function Test-StickySource([string]$s) { return ($s -eq 'notification' -or $s -eq 'conflict') }

function Update-BubbleHint {
    $n = $script:bubbleQueue.Count
    $bubbleHint.Text = if ($n -gt 0) { "点击查看下一条（还有 $n 条）" } else { '点击收起' }
}
function Open-BubbleNow([string]$text, [string]$source) {
    $script:bubbleSource = $source
    $bubbleText.Text = $text
    Update-BubbleHint
    $bubble.IsOpen = $true
    Show-Docked
    Hop  # 蹦一下吸引注意
}
function Show-Bubble([string]$text, [int]$seconds = 0, [string]$source = 'notification') {
    # seconds 参数仅保留兼容旧调用；所有气泡都必须点击后才收起。
    $item = [pscustomobject]@{ Text = $text; Source = $source }
    if ($source -ne 'manual' -and (Test-Dnd)) {
        if (Test-StickySource $source) { $script:bubbleQueue.Add($item) }
        return
    }
    if ($bubble.IsOpen -and (Test-StickySource $script:bubbleSource)) {
        if ($source -eq 'manual') {
            $script:bubbleQueue.Insert(0, [pscustomobject]@{ Text = $bubbleText.Text; Source = $script:bubbleSource })
        } elseif (Test-StickySource $source) {
            # 连续的同一条消息只留一份
            $last = if ($script:bubbleQueue.Count) { $script:bubbleQueue[$script:bubbleQueue.Count - 1].Text } else { $bubbleText.Text }
            if ($last -ne $text) { $script:bubbleQueue.Add($item); Update-BubbleHint; Hop }
            return
        } else { return }
    }
    Open-BubbleNow $text $source
}
function Show-NextBubble {
    if ($script:bubbleQueue.Count -eq 0) { $bubble.IsOpen = $false; return }
    $next = $script:bubbleQueue[0]
    $script:bubbleQueue.RemoveAt(0)
    Open-BubbleNow $next.Text $next.Source
}

# 点气泡：有排队消息就显示下一条，否则收起
$bubbleBorder.Add_MouseLeftButtonDown({
    Show-NextBubble
    $_.Handled = $true
})
$bubble.Add_Closed({ Request-HideDocked })

# ---------- 喝水滤镜：原生分层窗口，按物理像素覆盖每块显示器 ----------
# 不修改系统颜色设置；窗口透明且不激活，保留鼠标穿透。
# C# 源码单独放在变量里，启动后由后台 runspace 预编译，第一次提醒时不再卡顿。
$waterFilterSource = @"
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
function Initialize-WaterFilter {
    if ('OracleWaterFilter' -as [type]) { return }
    try { Add-Type $waterFilterSource } catch { if (-not ('OracleWaterFilter' -as [type])) { throw } }
}

# 计时规则：只累计"人在电脑前"的时间。
#   - 2 分钟以上没有键鼠输入：暂停累计；10 分钟以上：视为已离开休息，计时清零
#   - 到点时如果处于勿扰、锁屏、全屏或演示模式，先不弹，等情况解除后的下一次检查再弹
$script:waterActive   = $false
$script:waterElapsed  = 0
$waterIntervalSec     = 1800
$waterTickSec         = 30
$waterTimer = New-Object System.Windows.Threading.DispatcherTimer
$waterTimer.Interval = [TimeSpan]::FromSeconds($waterTickSec)
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
    $miSnooze.IsEnabled = $false
    if ($RestartTimer) {
        $script:waterElapsed = 0
        Write-WaterLog 'confirmed' '已恢复显示，30 分钟后再次提醒'
    }
}
function Show-WaterFilter([string]$source = 'manual') {
    try {
        Initialize-WaterFilter
        [OracleWaterFilter]::Show()
        $script:waterActive = $true
        $miWaterDone.IsEnabled = $true
        $miSnooze.IsEnabled = $true
        $waterFilterTimer.Start()
        Write-WaterLog $source ("淡蓝滤镜开启，屏幕数：" + [OracleWaterFilter]::Handles.Length)
    } catch {
        Hide-WaterFilter
        Write-WaterLog 'error' $_.Exception.Message
        $script:waterElapsed = 0
    }
}
$waterFilterTimer.Add_Tick({
    if (-not $script:waterActive) { return }
    try { [OracleWaterFilter]::Show() } catch {
        Write-WaterLog 'error' $_.Exception.Message
        Hide-WaterFilter -RestartTimer
    }
})

# ---------- 勿扰模式 ----------
function Start-Dnd {
    $script:dndUntil = [DateTime]::Now.AddHours(1)
    $pet.Opacity = 0.55
    if ($script:waterActive) { Hide-WaterFilter; $script:waterElapsed = $waterIntervalSec }   # 勿扰结束后再提醒
    if ($bubble.IsOpen -and -not (Test-StickySource $script:bubbleSource)) { $bubble.IsOpen = $false }
    Write-WaterLog 'dnd' '开启勿扰 1 小时'
}
function Stop-Dnd {
    $script:dndUntil = [DateTime]::MinValue
    $pet.Opacity = 1.0
    Write-WaterLog 'dnd' '结束勿扰'
    if ($script:bubbleQueue.Count -gt 0 -and -not $bubble.IsOpen) { Show-NextBubble }
}

$waterTimer.Add_Tick({
    try {
        if ($script:dndUntil -ne [DateTime]::MinValue -and -not (Test-Dnd)) { Stop-Dnd }
        if ($script:waterActive) { return }
        $idle = 0.0; $ns = 5
        if ('OracleSyncWin32' -as [type]) {
            $idle = [OracleSyncWin32]::IdleSeconds()
            $ns   = [OracleSyncWin32]::NotificationState()
        }
        if ($idle -ge 600) {
            if ($script:waterElapsed -gt 0) { Write-WaterLog 'away' ('离开 {0:N0} 分钟，计时清零' -f ($idle / 60)) }
            $script:waterElapsed = 0
            return
        }
        if ($idle -ge 120) { return }
        if ($script:waterElapsed -lt $waterIntervalSec) { $script:waterElapsed += $waterTickSec }
        if ($script:waterElapsed -lt $waterIntervalSec) { return }
        if (Test-Dnd) { return }
        if (@(1, 2, 3, 4, 7) -contains $ns) { return }   # 锁屏 / 全屏 / 演示模式：推迟
        Show-WaterFilter 'fire'
    } catch { Write-WaterLog 'error' $_.Exception.Message }
})
$waterTimer.Start()
$miWater.Add_Click({ Show-WaterFilter 'manual' })
$miWaterDone.Add_Click({ Hide-WaterFilter -RestartTimer })
$miSnooze.Add_Click({
    Hide-WaterFilter
    $script:waterElapsed = $waterIntervalSec - 300
    Write-WaterLog 'snooze' '5 分钟后再提醒'
})
$miDnd.Add_Click({
    if (Test-Dnd) { Stop-Dnd; Show-Bubble '已结束勿扰' -source 'manual' }
    else { Start-Dnd; Show-Bubble '🌙 勿扰 1 小时：暂停气泡和喝水提醒' -source 'manual' }
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
$script:syncLastFile = $null   # 最近同步的文件 @{ at; name }，来自 /rest/stats/folder

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
# 所有后台任务共用一个小线程池：不再每次轮询都新建一个 runspace（创建 runspace 本身就要几十毫秒和不少内存）
$bgPool = [RunspaceFactory]::CreateRunspacePool(1, 3)
$bgPool.Open()
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
    # Windows PowerShell 5.1 的 Invoke-RestMethod 对不带 charset 的 JSON（Syncthing 就是）会按
    # Latin-1 解码，中文文件名全成乱码（"新建…" → "æ°å»º…"）。这里统一拿原始字节按 UTF-8 解码。
    function Invoke-SyncJson([string]$Uri, [int]$TimeoutSec = 2) {
        $resp = Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing
        $bytes = if ($resp.Content -is [byte[]]) { $resp.Content } else { $resp.RawContentStream.ToArray() }
        return ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
    }
    try {
        $fcfg = Invoke-SyncJson "http://127.0.0.1:8384/rest/config/folders/$folderId"
    } catch { return @{ kind = 'error'; tip = ('Syncthing 无响应：' + $_.Exception.Message) } }
    if ($fcfg.paused) { return @{ kind = 'paused'; tip = '已暂停同步（右键 → 暂停 / 恢复同步 可恢复）' } }
    try {
        $st = Invoke-SyncJson "http://127.0.0.1:8384/rest/db/status?folder=$folderId"
        $cn = Invoke-SyncJson 'http://127.0.0.1:8384/rest/system/connections'
    } catch { return @{ kind = 'error'; tip = ('Syncthing 无响应：' + $_.Exception.Message) } }
    # 最近一次收到/改动的文件（可选信息，取不到不影响状态判断）
    $lastAt = $null; $lastName = $null
    try {
        $fs = Invoke-SyncJson 'http://127.0.0.1:8384/rest/stats/folder'
        $lf = $fs.$folderId.lastFile
        if ($lf -and $lf.at) { $lastAt = [string]$lf.at; $lastName = [string]$lf.filename }
    } catch {}
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
        lastAt    = $lastAt
        lastName  = $lastName
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
function Format-SyncTime([string]$iso) {
    try { $d = [DateTime]::Parse($iso).ToLocalTime() } catch { return $null }
    if ($d.Year -lt 2000) { return $null }
    $today = [DateTime]::Today
    if ($d.Date -eq $today)             { return '今天 ' + $d.ToString('HH:mm') }
    if ($d.Date -eq $today.AddDays(-1)) { return '昨天 ' + $d.ToString('HH:mm') }
    return $d.ToString('MM-dd HH:mm')
}
# "最近同步：今天 14:32 · 文件名"，文件名过长时截断
function Get-LastSyncLine {
    $l = $script:syncLastFile
    if (-not $l) { return $null }
    $when = Format-SyncTime $l.at
    if (-not $when) { return $null }
    $name = [IO.Path]::GetFileName(([string]$l.name).TrimEnd('/', '\'))
    if ($name.Length -gt 22) { $name = $name.Substring(0, 21) + '…' }
    if ($name) { return "最近同步：$when · $name" } else { return "最近同步：$when" }
}

function Apply-SyncResult($raw) {
    if ($raw.ContainsKey('lastAt') -and $raw.lastAt) { $script:syncLastFile = @{ at = $raw.lastAt; name = $raw.lastName } }
    $res = Resolve-SyncKind $raw
    $k = $res.kind
    $dotTip = $res.tip
    $lastLine = Get-LastSyncLine
    if ($lastLine) { $dotTip += "`n" + $lastLine }
    Set-StatusDot $k ($dotTip + "`n点击打开 Syncthing 管理页")
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
            $script:pollPS.RunspacePool = $bgPool
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
# 2026-11-06 实测：进程还活着、气泡还能弹，但主窗口被外部程序 ShowWindow(SW_HIDE) 藏掉了
# （IsWindowVisible=False，WPF 的 Visibility 仍是 Visible，所以 $win.Show() 无效）。
# 这里按原生句柄检查，被藏/被最小化就用 SW_SHOWNOACTIVATE 放回来，并记下当时的前台程序方便追查。
function Ensure-Visible {
    if (-not ('OracleSyncWin32' -as [type]) -or -not ([OracleSyncWin32].GetMethod('IsWindowVisible'))) { return }
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
    if ($h -eq [IntPtr]::Zero) { return }
    $hidden = -not [OracleSyncWin32]::IsWindowVisible($h)
    $iconic = [OracleSyncWin32]::IsIconic($h)
    if (-not $hidden -and -not $iconic) { return }
    $fgName = ''
    try {
        $fg = [OracleSyncWin32]::GetForegroundWindow(); $fp = 0
        [void][OracleSyncWin32]::GetWindowThreadProcessId($fg, [ref]$fp)
        $fgName = (Get-Process -Id $fp -ErrorAction SilentlyContinue).ProcessName
    } catch {}
    [void][OracleSyncWin32]::ShowWindow($h, 4)   # SW_SHOWNOACTIVATE
    Write-ExitLog ("window restored (hidden=$hidden iconic=$iconic foreground=$fgName)")
}
$topmostTimer.Add_Tick({
    try { Ensure-Visible } catch {}
    try { Set-AlwaysOnTop } catch {}
    try { Ensure-OnScreen } catch {}   # 显示器变化后把跑出屏幕的桌宠拉回来
})
# 桌宠一旦失去前台（多半是别的窗口冒到前面），立刻顶回去，恢复更跟手。
$win.Add_Deactivated({ try { Set-AlwaysOnTop } catch {} })

# ---------- 通用后台任务 ----------
# Start-BgJob 把脚本丢进线程池执行，$bgTimer 在 UI 线程上收割结果并调用回调。
# 后台脚本绝不能碰 WPF 对象，只返回数据；回调运行在 UI 线程，可以随意刷新界面。
$script:bgJobs = New-Object System.Collections.Generic.List[object]
function Start-BgJob([scriptblock]$job, [object[]]$arguments = @(), [scriptblock]$onDone = $null) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $bgPool
    [void]$ps.AddScript($job.ToString())
    foreach ($a in $arguments) { [void]$ps.AddArgument($a) }
    $script:bgJobs.Add([pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke(); Done = $onDone })
    if (-not $bgTimer.IsEnabled) { $bgTimer.Start() }
}
$bgTimer = New-Object System.Windows.Threading.DispatcherTimer
$bgTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$bgTimer.Add_Tick({
    for ($i = $script:bgJobs.Count - 1; $i -ge 0; $i--) {
        $j = $script:bgJobs[$i]
        if (-not $j.Handle.IsCompleted) { continue }
        $script:bgJobs.RemoveAt($i)
        $out = $null; $err = $null
        try { $out = $j.PS.EndInvoke($j.Handle) | Select-Object -Last 1 } catch { $err = $_.Exception.Message }
        try { $j.PS.Dispose() } catch {}
        if ($j.Done) { try { & $j.Done $out $err } catch {} }
    }
    if ($script:bgJobs.Count -eq 0) { $bgTimer.Stop() }
})

# ---------- 启动后预热：后台编译 C# 类型 + 清理过大的日志 ----------
# Add-Type 生成的类型对整个进程可见，所以在后台 runspace 里编译，UI 线程直接就能用。
$commonLib = Join-Path $PSScriptRoot 'oracle-sync-common.ps1'
function Start-Warmup {
    $logs = @($exitLog, $waterLog, (Join-Path $stateDir 'codex-notify.log'), (Join-Path $stateDir 'notify-pet.log'))
    Start-BgJob {
        param($lib, $waterSrc, $logs)
        . $lib
        try { Initialize-OracleWin32 } catch {}
        try { if (-not ('OracleWaterFilter' -as [type])) { Add-Type $waterSrc } } catch {}
        foreach ($l in $logs) { Limit-OracleLog $l }
    } @($commonLib, $waterFilterSource, $logs)
}

# ---------- 同步冲突文件检测 ----------
# Syncthing 遇到两边同时修改时会生成 "文件名.sync-conflict-日期-时间-设备.扩展名" 副本，很容易被忽略。
# 每 10 分钟在后台扫一遍同步目录（跳过 .stversions 等目录），发现新的冲突就弹气泡提醒。
$script:conflicts        = @()
$script:conflictKnown    = @{}
$script:conflictScanning = $false
$conflictScript = {
    param($root)
    $found = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            foreach ($d in [IO.Directory]::EnumerateDirectories($dir)) {
                $n = [IO.Path]::GetFileName($d)
                if ($n -eq '.stversions' -or $n -eq '.stfolder' -or $n -eq '.git' -or $n -eq 'node_modules') { continue }
                $stack.Push($d)
            }
            foreach ($f in [IO.Directory]::EnumerateFiles($dir, '*.sync-conflict-*')) { $found.Add($f) }
        } catch {}
    }
    return ($found -join "`n")
}
function Start-ConflictScan {
    if ($script:conflictScanning) { return }
    $script:conflictScanning = $true
    Start-BgJob $conflictScript @($root) {
        param($out, $err)
        $script:conflictScanning = $false
        if ($err) { return }
        $list = @(([string]$out) -split "`n" | Where-Object { $_ })
        $new  = @($list | Where-Object { -not $script:conflictKnown.ContainsKey($_) })
        $script:conflicts = $list
        $script:conflictKnown = @{}
        foreach ($f in $list) { $script:conflictKnown[$f] = $true }
        if ($list.Count -gt 0) {
            $miConflict.Header = "同步冲突文件（$($list.Count)）"
            $miConflict.Visibility = 'Visible'
        } else { $miConflict.Visibility = 'Collapsed' }
        if ($new.Count -gt 0) {
            $names = ($new | Select-Object -First 3 | ForEach-Object { [IO.Path]::GetFileName($_) }) -join "`n"
            $more  = if ($new.Count -gt 3) { "`n…等 $($new.Count) 个" } else { '' }
            Show-Bubble ("⚠️ 发现 $($new.Count) 个同步冲突文件：`n" + $names + $more + "`n右键 → 同步冲突文件 查看") -source 'conflict'
        }
    }
}
$conflictTimer = New-Object System.Windows.Threading.DispatcherTimer
$conflictTimer.Interval = [TimeSpan]::FromMinutes(10)
$conflictTimer.Add_Tick({ try { Start-ConflictScan } catch {} })
# 开机后等 1 分钟再扫第一次，避开 Syncthing 自己的启动扫描
$conflictFirst = New-Object System.Windows.Threading.DispatcherTimer
$conflictFirst.Interval = [TimeSpan]::FromSeconds(60)
$conflictFirst.Add_Tick({ $conflictFirst.Stop(); try { Start-ConflictScan } catch {}; $conflictTimer.Start() })

$miConflict.Add_Click({
    $list = @($script:conflicts | Where-Object { Test-Path -LiteralPath $_ })
    if ($list.Count -eq 0) {
        $miConflict.Visibility = 'Collapsed'
        Show-Bubble '冲突文件已经处理完了 👍' -source 'manual'
        return
    }
    # 在资源管理器中定位第一个，并列出前几个的相对路径
    Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $list[0])
    $rel  = ($list | Select-Object -First 5 | ForEach-Object { $_.Substring($root.Length).TrimStart('\') }) -join "`n"
    $more = if ($list.Count -gt 5) { "`n…共 $($list.Count) 个" } else { '' }
    Show-Bubble ("同步冲突文件（已定位第一个）：`n" + $rel + $more + "`n对比后保留需要的版本，删掉冲突副本即可") -source 'manual'
    Start-ConflictScan
})

# 窗口内容渲染完成后再启动轮询：先让桌宠瞬间出现，不被网络请求拖住开机。
$win.Add_ContentRendered({
    try { Ensure-OnScreen } catch {}
    if ($script:dock) { try { $win.Left = Get-DockX $script:dock $false } catch {} }
    try { Pump-SyncPoll } catch {}   # 立刻发起第一次轮询（后台线程，不阻塞）
    $syncTimer.Start()
    $topmostTimer.Start()
    $conflictFirst.Start()
    try { Start-Warmup } catch {}
    if ($WaterPreview) { Show-WaterFilter 'preview' }
})

# 右键菜单"查看同步状态"——显示最近一次后台轮询的缓存结果，并顺手触发一次刷新。
# 以 manual 身份弹出（不会被未读通知挡住），之后改记为 sync，让轮询继续刷新文字。
$miSync.Add_Click({
    $tip = if ($script:syncLast -and $script:syncLast.tip) { $script:syncLast.tip } else { 'Syncthing 状态：检测中…' }
    Show-Bubble $tip -source 'manual'
    $script:bubbleSource = 'sync'
    try { Pump-SyncPoll } catch {}
})

# 右键菜单"暂停 / 恢复同步"——网络请求放到后台执行，界面不会卡住
$script:pauseBusy = $false
$miPause.Add_Click({
    if (-not $script:syncApiKey -or -not $script:syncFolderId) {
        Show-Bubble '找不到 Syncthing 配置，无法切换' -source 'manual'
        return
    }
    if ($script:pauseBusy) { return }
    $script:pauseBusy = $true
    Start-BgJob {
        param($apiKey, $folderId)
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $ar = $c.BeginConnect('127.0.0.1', 8384, $null, $null)
            if (-not ($ar.AsyncWaitHandle.WaitOne(300) -and $c.Connected)) { return @{ ok = $false; offline = $true } }
        } catch { return @{ ok = $false; offline = $true } } finally { $c.Close() }
        $headers = @{ 'X-API-Key' = $apiKey; 'Content-Type' = 'application/json' }
        try {
            $uri  = "http://127.0.0.1:8384/rest/config/folders/$folderId"
            $fcfg = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 3
            $newPaused = -not [bool]$fcfg.paused
            $body = (@{ paused = $newPaused } | ConvertTo-Json -Compress)
            Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $body -TimeoutSec 3 | Out-Null
            return @{ ok = $true; paused = $newPaused }
        } catch { return @{ ok = $false; error = $_.Exception.Message } }
    } @($script:syncApiKey, $script:syncFolderId) {
        param($r, $err)
        $script:pauseBusy = $false
        if ($err)       { Show-Bubble ('切换失败：' + $err) -source 'manual'; return }
        if (-not $r)    { Show-Bubble '切换失败：没有返回结果' -source 'manual'; return }
        if ($r.offline) { Show-Bubble 'Syncthing 没在跑，先把它启动起来' -source 'manual'; return }
        if (-not $r.ok) { Show-Bubble ('切换失败：' + $r.error) -source 'manual'; return }
        if ($r.paused)  { Show-Bubble '⏸ 已暂停 Oracle-Sync 同步' -source 'manual' }
        else            { Show-Bubble '▶ 已恢复 Oracle-Sync 同步' -source 'manual' }
        try { Pump-SyncPoll } catch {}
    }
})

# 打开菜单前刷新动态内容：状态信息行、暂停/恢复、勿扰剩余时间、皮肤勾选
$menu.Add_Opened({
    Update-SkinMenu
    Update-SizeMenu
    $info = if ($script:syncLast -and $script:syncLast.tip) { $script:syncLast.tip } else { 'Syncthing 状态：检测中…' }
    $lastLine = Get-LastSyncLine
    if ($lastLine) { $info += "`n" + $lastLine }
    $miInfo.Header = $info
    if ($script:syncLastKind -eq 'paused') { $miPause.Header = '恢复同步'; $miPause.Icon = [string][char]0xE768 }
    else                                    { $miPause.Header = '暂停同步'; $miPause.Icon = [string][char]0xE769 }
    if (Test-Dnd) {
        $left = [Math]::Ceiling(($script:dndUntil - [DateTime]::Now).TotalMinutes)
        $miDnd.Header = "结束勿扰（剩 $left 分钟）"
    } else { $miDnd.Header = '勿扰 1 小时' }
})
$menu.Add_Closed({ Request-HideDocked })

# 窗口关闭与未处理异常的记录（只记录，不改变异常是否终止进程的行为）
$win.Add_Closed({ Write-ExitLog 'window closed' })
$win.Dispatcher.add_UnhandledException({ param($s, $e) Write-ExitLog ('unhandled: ' + $e.Exception.ToString()) })

try {
    [void]$win.ShowDialog()
} finally {
    Write-ExitLog 'finally reached'
    Hide-WaterFilter
    foreach ($t in @($waterTimer, $waterFilterTimer, $timer, $notifyPoll, $syncTimer, $topmostTimer,
                     $bgTimer, $conflictTimer, $conflictFirst, $slideTimer, $dockHideTimer)) {
        if ($t) { $t.Stop() }
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
