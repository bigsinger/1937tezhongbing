@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-RealAssetTests.ps1" %*
exit /b %errorlevel%
