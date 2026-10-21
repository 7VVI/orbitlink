@echo off
rem Builds and runs the native media module verification.
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
cd /d "%~dp0"
set SDK=%WindowsSdkDir%Include\%WindowsSDKVersion%
cl /nologo /EHsc /std:c++17 /O2 /MT /W3 ^
  /I"%SDK%\um" /I"%SDK%\shared" /I"%SDK%\winrt" ^
  /DWIN32_LEAN_AND_MEAN /DUNICODE /D_UNICODE ^
  orbitlink_encoder.cpp orbitlink_encoder_test.cpp ^
  /link /LIBPATH:"%SDK%\um\x64" mfplat.lib mf.lib mfreadwrite.lib d3d11.lib dxgi.lib windowsapp.lib ole32.lib uuid.lib ^
  /out:orbitlink_encoder_test.exe
if errorlevel 1 exit /b 1
copy /y "%~dp0..\..\runner\resources\turbojpeg.dll" . >nul
orbitlink_encoder_test.exe
