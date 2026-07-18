@echo off
setlocal EnableExtensions EnableDelayedExpansion
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
cl /nologo /LD /O2 /MT /EHsc /W4 /DWIN32 /D_WINDOWS ^
  /Fo"%~dp0build\\" /Fd"%~dp0build\\" ^
  "%~dp0dinput_proxy.cpp" "%~dp0dinput_proxy.def" ^
  /link /MACHINE:X86 /OUT:"%~dp0build\dinput.dll" ^
  /IMPLIB:"%~dp0build\dinput_proxy.lib" ^
  /PDB:"%~dp0build\dinput.pdb" user32.lib dxguid.lib
exit /b %errorlevel%
