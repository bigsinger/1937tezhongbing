@echo off
setlocal
if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Import-ModAssets.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Import-ModAssets.ps1" -OutputDirectory "%~1"
)
exit /b %errorlevel%
