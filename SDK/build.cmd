@echo off
setlocal EnableExtensions EnableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Test-SdkSingleSource.ps1"
if errorlevel 1 exit /b %errorlevel%
where cl.exe >nul 2>nul
if errorlevel 1 (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if not exist "!VSWHERE!" (
    echo Visual Studio C++ build tools were not found.
    exit /b 1
  )
  for /f "usebackq tokens=*" %%I in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%I"
  if not defined VSINSTALL (
    echo Visual Studio C++ x86 tools were not found.
    exit /b 1
  )
  call "!VSINSTALL!\VC\Auxiliary\Build\vcvars32.bat" >nul
  if errorlevel 1 exit /b 1
)
if not exist "%~dp0build" mkdir "%~dp0build"
cl /nologo /EHsc /std:c++17 /utf-8 /O2 /MT /W4 /WX ^
  /I"%~dp0include" ^
  "%~dp0tests\sdk_tests.cpp" ^
  /Fe:"%~dp0build\M1937SDK.Tests.exe" ^
  /Fo:"%~dp0build\\" ^
  /link /MACHINE:X86 /Brepro
if errorlevel 1 exit /b %errorlevel%
if /i "%~1"=="--compile-only" (
  echo M1937SDK compile-only validation passed.
  exit /b 0
)
"%~dp0build\M1937SDK.Tests.exe" "%~dp0..\Mod\M1937.exe"
exit /b %errorlevel%
