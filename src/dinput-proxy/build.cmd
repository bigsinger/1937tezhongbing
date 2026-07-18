@echo off
setlocal
call "D:\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat" >nul
if errorlevel 1 exit /b 1
if not exist "%~dp0build" mkdir "%~dp0build"
cl /nologo /LD /O2 /MT /EHsc /W4 /DWIN32 /D_WINDOWS ^
  /Fo"%~dp0build\\" /Fd"%~dp0build\\" ^
  "%~dp0dinput_proxy.cpp" "%~dp0dinput_proxy.def" ^
  /link /OUT:"%~dp0build\dinput.dll" ^
  /IMPLIB:"%~dp0build\dinput_proxy.lib" ^
  /PDB:"%~dp0build\dinput.pdb" user32.lib dxguid.lib
exit /b %errorlevel%
