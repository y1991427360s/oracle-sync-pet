# pet.ps1 与 open-sync-folder.ps1 共用的函数。通过点源（. .\oracle-sync-common.ps1）加载。
# 这里只定义函数，不做任何耗时操作：C# 类型在第一次真正用到时才编译（Add-Type 底层要拉起 csc.exe）。
# 桌宠会在启动后把编译放进后台 runspace 预热；Add-Type 生成的类型对整个进程可见。

$script:OracleWin32Source = @"
using System;
using System.Runtime.InteropServices;
public static class OracleSyncWin32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    // 距离最后一次键盘/鼠标输入的秒数
    public static double IdleSeconds() {
        var li = new LASTINPUTINFO(); li.cbSize = (uint)Marshal.SizeOf(li);
        if (!GetLastInputInfo(ref li)) return 0;
        return unchecked((uint)Environment.TickCount - li.dwTime) / 1000.0;
    }

    // QUERY_USER_NOTIFICATION_STATE：1 锁屏/屏保，2 全屏应用，3 D3D 全屏，4 演示模式，5 正常，6 专注/安静时间，7 Windows 应用全屏
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    public static int NotificationState() {
        int s; return SHQueryUserNotificationState(out s) == 0 ? s : 5;
    }
}
"@

function Initialize-OracleWin32 {
    if ('OracleSyncWin32' -as [type]) { return }
    # 后台预热可能正在编译同名类型；重复 Add-Type 会报"类型已存在"，此时类型已可用，忽略即可。
    try { Add-Type $script:OracleWin32Source } catch { if (-not ('OracleSyncWin32' -as [type])) { throw } }
}

# 打开目标文件夹：已有资源管理器窗口就激活它（绕过前台窗口限制），否则新开一个。
function Open-OracleSyncFolder([string]$target) {
    Initialize-OracleWin32
    $target = $target.TrimEnd('\')
    $shell = New-Object -ComObject Shell.Application
    $found = $null
    foreach ($w in $shell.Windows()) {
        try {
            $u = $w.LocationURL
            if (-not $u) { continue }
            if ([Uri]::new($u).LocalPath.TrimEnd('\') -ieq $target) { $found = $w; break }
        } catch {}
    }
    if (-not $found) { Start-Process explorer.exe -ArgumentList "`"$target`""; return }
    $hwnd = [IntPtr]$found.HWND
    if ([OracleSyncWin32]::IsIconic($hwnd)) { [void][OracleSyncWin32]::ShowWindow($hwnd, 9) }
    $fg = [OracleSyncWin32]::GetForegroundWindow()
    $pidOut = 0
    $fgTid  = [OracleSyncWin32]::GetWindowThreadProcessId($fg, [ref]$pidOut)
    $curTid = [OracleSyncWin32]::GetCurrentThreadId()
    [void][OracleSyncWin32]::AttachThreadInput($fgTid, $curTid, $true)
    [void][OracleSyncWin32]::SetForegroundWindow($hwnd)
    [void][OracleSyncWin32]::AttachThreadInput($fgTid, $curTid, $false)
}

# 启动桌宠：交给资源管理器外壳（桌面的 IShellDispatch）去执行 pet.vbs，桌宠的父进程就是 explorer，
# 不会随调用方（Claude Code / WorkBuddy / 终端）退出或清理子进程而被连带强杀。外壳不可用时退回直接启动。
function Start-OraclePet([string]$vbs) {
    try {
        $hwnd = 0
        # SWC_DESKTOP = 8, SWFO_NEEDDISPATCH = 1
        $desktop = (New-Object -ComObject Shell.Application).Windows().FindWindowSW([ref]0, [ref]0, 8, [ref]$hwnd, 1)
        $desktop.Document.Application.ShellExecute('wscript.exe', "`"$vbs`"", (Split-Path $vbs), 'open', 0)
        return $true
    } catch {
        Start-Process wscript.exe -ArgumentList "`"$vbs`""
        return $false
    }
}

# 日志超过上限时只保留末尾若干行，避免无限增长。
function Limit-OracleLog([string]$path, [int]$maxBytes = 256KB, [int]$keepLines = 1000) {
    try {
        if (-not (Test-Path $path)) { return }
        if ((Get-Item $path).Length -le $maxBytes) { return }
        $tail = Get-Content $path -Tail $keepLines -Encoding UTF8
        Set-Content -Path $path -Value $tail -Encoding UTF8
    } catch {}
}

# ---------- Claude Code Stop hook（install / uninstall 共用） ----------
# 只增删"调用 notify-pet 的那一条"，其他 Stop hook（比如 Bark 手机通知）原样保留。
# Windows 上必须用 command=powershell.exe + 独立 args 的 exec 形式，shell 字符串形式在本机会让 Claude Code 退出时段错误。
function Update-OracleClaudeHook([string]$notifyScript, [switch]$Remove) {
    $path = Join-Path $env:USERPROFILE '.claude\settings.json'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if (Test-Path $path) {
        $raw = [IO.File]::ReadAllText($path)
        Copy-Item $path ("$path.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
        $cfg = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    } else {
        if ($Remove) { return '未找到 Claude Code 配置，跳过' }
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        $cfg = [pscustomobject]@{}
    }
    if (-not $cfg.PSObject.Properties['hooks']) { $cfg | Add-Member hooks ([pscustomobject]@{}) }
    $groups = @()
    if ($cfg.hooks.PSObject.Properties['Stop']) { $groups = @($cfg.hooks.Stop) }

    # 去掉旧的桌宠 hook（不论当初写的是哪个盘符的路径）
    $kept = @()
    foreach ($g in $groups) {
        $hs = @($g.hooks | Where-Object { -not ((([string]$_.command) + ' ' + (@($_.args) -join ' ')) -match 'notify-pet') })
        if ($hs.Count -gt 0) { $g.hooks = $hs; $kept += $g }
    }
    if (-not $Remove) {
        $kept += [pscustomobject]@{ hooks = @([pscustomobject]@{
            type    = 'command'
            command = 'powershell.exe'
            args    = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                        '-File', $notifyScript, '-Source', 'Claude Code')
            timeout = 10
        }) }
    }
    if ($cfg.hooks.PSObject.Properties['Stop']) { $cfg.hooks.Stop = $kept }
    else { $cfg.hooks | Add-Member Stop $kept }
    [IO.File]::WriteAllText($path, ($cfg | ConvertTo-Json -Depth 64), $utf8)
    if ($Remove) { return "已从 $path 移除桌宠通知 hook（其他 Stop hook 保留 $($kept.Count) 组）" }
    return "已写入 $path（Stop hook 共 $($kept.Count) 组）"
}
