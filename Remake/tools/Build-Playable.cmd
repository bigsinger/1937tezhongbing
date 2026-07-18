@echo off
setlocal
pushd "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Build-Playable.ps1" %*
set "exitCode=%ERRORLEVEL%"
popd
exit /b %exitCode%
