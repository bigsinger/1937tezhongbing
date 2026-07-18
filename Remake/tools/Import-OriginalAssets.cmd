@echo off
setlocal
if "%~1"=="" (
  echo Usage: Import-OriginalAssets.cmd "path-to-original-game" [output-directory]
  exit /b 1
)
if "%~2"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Import-OriginalAssets.ps1" -GameDirectory "%~1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Import-OriginalAssets.ps1" -GameDirectory "%~1" -OutputDirectory "%~2"
)
exit /b %errorlevel%
