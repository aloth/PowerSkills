<#
.SYNOPSIS
    Desktop skill — screenshots, window management, keystrokes.
.EXAMPLE
    .\desktop.ps1 screenshot --out-file screen.png
    .\desktop.ps1 windows
    .\desktop.ps1 keys --keys "{ENTER}" --window "Notepad"
#>
param(
    [Parameter(Position=0)] [string]$Action,
    [Parameter(ValueFromRemainingArguments)] [string[]]$Rest,
    [hashtable]$Args_,
    [hashtable]$Config
)

# ─── Standalone bootstrap ───
$_standalone = (-not $Args_ -or $Args_.Count -eq 0) -and -not (Get-Variable -Name SkillsRoot -Scope Script -ErrorAction SilentlyContinue)
if ($_standalone) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "lib\bootstrap.ps1")
    if ($Rest) { $Args_ = Parse-CliArgs -Arguments $Rest } else { $Args_ = @{} }
    if (-not $Config) { $Config = @{} }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Win32 APIs
if (-not ([System.Management.Automation.PSTypeName]'PSWin32').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class PSWin32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public const int SW_RESTORE = 9;
    public const int SW_MINIMIZE = 6;
    public const int SW_MAXIMIZE = 3;

    public static List<IntPtr> GetAllWindows() {
        var windows = new List<IntPtr>();
        EnumWindows((hWnd, lParam) => { windows.Add(hWnd); return true; }, IntPtr.Zero);
        return windows;
    }
}
"@
}

function Find-Window {
    param([string]$Title)
    foreach ($hWnd in [PSWin32]::GetAllWindows()) {
        $sb = New-Object System.Text.StringBuilder 256
        [PSWin32]::GetWindowText($hWnd, $sb, 256) | Out-Null
        $name = $sb.ToString()
        if ($name -like "*$Title*" -and [PSWin32]::IsWindowVisible($hWnd)) {
            return @{ hWnd = $hWnd; title = $name }
        }
    }
    return $null
}

# ─── Main logic ───
function Invoke-DesktopAction {
    switch ($Action) {
        "screenshot" {
            $outFile = $Args_.'out-file'
            if (-not $outFile) { throw "Required: --out-file" }

            if ($Args_.window) {
                $win = Find-Window -Title $Args_.window
                if (-not $win) { throw "Window '$($Args_.window)' not found" }
                [PSWin32]::ShowWindow($win.hWnd, [PSWin32]::SW_RESTORE) | Out-Null
                [PSWin32]::SetForegroundWindow($win.hWnd) | Out-Null
                Start-Sleep -Milliseconds 500

                $rect = New-Object PSWin32+RECT
                [PSWin32]::GetWindowRect($win.hWnd, [ref]$rect) | Out-Null
                $w = $rect.Right - $rect.Left
                $h = $rect.Bottom - $rect.Top

                $bmp = New-Object System.Drawing.Bitmap($w, $h)
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
                $gfx.Dispose()
                $bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                return @{ saved = $outFile; window = $win.title; width = $w; height = $h }
            } else {
                $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
                $gfx.Dispose()
                $bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                return @{ saved = $outFile; width = $bounds.Width; height = $bounds.Height }
            }
        }
        "windows" {
            $result = @()
            foreach ($hWnd in [PSWin32]::GetAllWindows()) {
                if (-not [PSWin32]::IsWindowVisible($hWnd)) { continue }
                $sb = New-Object System.Text.StringBuilder 256
                [PSWin32]::GetWindowText($hWnd, $sb, 256) | Out-Null
                $title = $sb.ToString()
                if ([string]::IsNullOrWhiteSpace($title)) { continue }
                $procId = [uint32]0
                [PSWin32]::GetWindowThreadProcessId($hWnd, [ref]$procId) | Out-Null
                $procName = ""
                try { $procName = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName } catch {}
                $result += @{ title = $title; pid = $procId; process = $procName; hwnd = $hWnd.ToInt64() }
            }
            return $result
        }
        "focus" {
            if (-not $Args_.window) { throw "Required: --window" }
            $win = Find-Window -Title $Args_.window
            if (-not $win) { throw "Window '$($Args_.window)' not found" }
            [PSWin32]::ShowWindow($win.hWnd, [PSWin32]::SW_RESTORE) | Out-Null
            [PSWin32]::SetForegroundWindow($win.hWnd) | Out-Null
            return @{ focused = $win.title }
        }
        "minimize" {
            if (-not $Args_.window) { throw "Required: --window" }
            $win = Find-Window -Title $Args_.window
            if (-not $win) { throw "Window '$($Args_.window)' not found" }
            [PSWin32]::ShowWindow($win.hWnd, [PSWin32]::SW_MINIMIZE) | Out-Null
            return @{ minimized = $win.title }
        }
        "maximize" {
            if (-not $Args_.window) { throw "Required: --window" }
            $win = Find-Window -Title $Args_.window
            if (-not $win) { throw "Window '$($Args_.window)' not found" }
            [PSWin32]::ShowWindow($win.hWnd, [PSWin32]::SW_MAXIMIZE) | Out-Null
            return @{ maximized = $win.title }
        }
        "keys" {
            if (-not $Args_.keys) { throw "Required: --keys" }
            if ($Args_.window) {
                $win = Find-Window -Title $Args_.window
                if ($win) {
                    [PSWin32]::ShowWindow($win.hWnd, [PSWin32]::SW_RESTORE) | Out-Null
                    [PSWin32]::SetForegroundWindow($win.hWnd) | Out-Null
                    Start-Sleep -Milliseconds 300
                }
            }
            [System.Windows.Forms.SendKeys]::SendWait($Args_.keys)
            return @{ sent = $Args_.keys }
        }
        "launch" {
            if (-not $Args_.app) { throw "Required: --app" }
            $waitMs = if ($Args_.'wait-ms') { [int]$Args_.'wait-ms' } else { 3000 }
            if ($Args_.'app-args') {
                Start-Process $Args_.app -ArgumentList $Args_.'app-args'
            } else {
                Start-Process $Args_.app
            }
            Start-Sleep -Milliseconds $waitMs
            return @{ launched = $Args_.app }
        }
        default {
            throw "Unknown action: $Action. Use: screenshot, windows, focus, minimize, maximize, keys, launch"
        }
    }
}

# ─── Execute ───
if ($_standalone) {
    try { $result = Invoke-DesktopAction; Write-SkillResult -Data $result }
    catch { Write-SkillError -Message $_.Exception.Message }
} else {
    return (Invoke-DesktopAction)
}
