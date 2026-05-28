$ErrorActionPreference = 'SilentlyContinue'

$target = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@

function Activate-Window([IntPtr]$hwnd) {
    if ([Win32]::IsIconic($hwnd)) { [void][Win32]::ShowWindow($hwnd, 9) }
    $fg = [Win32]::GetForegroundWindow()
    $fgPid = 0
    $fgTid = [Win32]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $curTid = [Win32]::GetCurrentThreadId()
    [void][Win32]::AttachThreadInput($fgTid, $curTid, $true)
    [void][Win32]::SetForegroundWindow($hwnd)
    [void][Win32]::AttachThreadInput($fgTid, $curTid, $false)
}

$shell = New-Object -ComObject Shell.Application
$found = $null
foreach ($win in $shell.Windows()) {
    try {
        $url = $win.LocationURL
        if ([string]::IsNullOrEmpty($url)) { continue }
        $path = [Uri]::new($url).LocalPath.TrimEnd('\')
        if ($path -ieq $target) { $found = $win; break }
    } catch {}
}

if ($found) {
    Activate-Window ([IntPtr]$found.HWND)
} else {
    Start-Process explorer.exe -ArgumentList "`"$target`""
}
