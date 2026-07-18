@echo off
setlocal
if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-RuntimeProbe.ps1"
) else if "%~2"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-RuntimeProbe.ps1" -GodotExecutable "%~1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-RuntimeProbe.ps1" -GodotExecutable "%~1" -OutputDirectory "%~2"
)
exit /b %errorlevel%
