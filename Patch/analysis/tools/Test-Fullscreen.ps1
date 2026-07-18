[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$GameDirectory
)

$ErrorActionPreference = 'Stop'
$gameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class FullscreenNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr window, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte virtualKey, byte scan,
        uint flags, UIntPtr extraInfo);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr window, uint message,
        UIntPtr wParam, IntPtr lParam);

    public static bool SetFullscreenMode(IntPtr window, bool fullscreen)
    {
        return PostMessage(window, 0x8075,
            new UIntPtr(fullscreen ? 1u : 2u), IntPtr.Zero);
    }
}
'@

function Send-AltEnter([IntPtr]$Window) {
    [FullscreenNative]::SetForegroundWindow($Window) | Out-Null
    Start-Sleep -Milliseconds 200
    [FullscreenNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [FullscreenNative]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [FullscreenNative]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero)
    [FullscreenNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
}

function Set-FullscreenMode([IntPtr]$Window, [bool]$Fullscreen) {
    # cnc-ddraw's own window message, equivalent to its Alt+Enter handler.
    [FullscreenNative]::SetFullscreenMode($Window, $Fullscreen) | Out-Null
}

function Get-WindowMeasurement([IntPtr]$Window, [string]$Mode) {
    $client = New-Object FullscreenNative+RECT
    $outer = New-Object FullscreenNative+RECT
    [FullscreenNative]::GetClientRect($Window, [ref]$client) | Out-Null
    [FullscreenNative]::GetWindowRect($Window, [ref]$outer) | Out-Null
    [pscustomobject]@{
        Mode = $Mode
        ClientWidth = $client.Right - $client.Left
        ClientHeight = $client.Bottom - $client.Top
        WindowLeft = $outer.Left
        WindowTop = $outer.Top
        WindowWidth = $outer.Right - $outer.Left
        WindowHeight = $outer.Bottom - $outer.Top
    }
}

function Wait-ClientSize([IntPtr]$Window, [int]$Width, [int]$Height,
        [bool]$ShouldMatch, [string]$Mode) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt 10) {
        $measurement = Get-WindowMeasurement $Window $Mode
        $matches = $measurement.ClientWidth -eq $Width -and
            $measurement.ClientHeight -eq $Height
        if ($matches -eq $ShouldMatch) {
            $measurement | Add-Member -NotePropertyName ToggleMilliseconds `
                -NotePropertyValue ([math]::Round($watch.Elapsed.TotalMilliseconds))
            return $measurement
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for mode: $Mode"
}

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = Join-Path $gameDirectory 'M1937.exe'
$startInfo.WorkingDirectory = $gameDirectory
$startInfo.UseShellExecute = $false
$game = [System.Diagnostics.Process]::Start($startInfo)

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 100
        $game.Refresh()
    } while ($game.MainWindowHandle -eq [IntPtr]::Zero -and
        -not $game.HasExited -and [DateTime]::UtcNow -lt $deadline)

    if ($game.MainWindowHandle -eq [IntPtr]::Zero) {
        throw 'Game window did not appear.'
    }

    Start-Sleep -Seconds 5
    $windowed = Get-WindowMeasurement $game.MainWindowHandle 'windowed-before'

    $primary = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    Set-FullscreenMode $game.MainWindowHandle $true
    $fullscreen = Wait-ClientSize $game.MainWindowHandle `
        $primary.Width $primary.Height $true 'fullscreen'

    Set-FullscreenMode $game.MainWindowHandle $false
    $restored = Wait-ClientSize $game.MainWindowHandle `
        $primary.Width $primary.Height $false 'windowed-after'

    [pscustomobject]@{
        PrimaryWidth = $primary.Width
        PrimaryHeight = $primary.Height
        ProcessResponding = $game.Responding
        WindowedBefore = $windowed
        Fullscreen = $fullscreen
        WindowedAfter = $restored
    } | ConvertTo-Json -Depth 3
}
finally {
    if (-not $game.HasExited) {
        $game.CloseMainWindow() | Out-Null
        if (-not $game.WaitForExit(1500)) {
            $game.Kill()
            $game.WaitForExit(1500) | Out-Null
        }
    }
}
