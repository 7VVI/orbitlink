@echo off
rem Builds and runs the Media Foundation H.264 codec verification.
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
cd /d "%~dp0"
set SDK=%WindowsSdkDir%Include\%WindowsSDKVersion%
cl /nologo /EHsc /std:c++17 /O2 /MT /W3 ^
  /I"%SDK%\um" /I"%SDK%\shared" /I"%SDK%\winrt" ^
  /DWIN32_LEAN_AND_MEAN /DUNICODE /D_UNICODE ^
  h264_codec.cpp h264_codec_test.cpp ^
  /link /LIBPATH:"%SDK%\um\x64" mfplat.lib mf.lib mfuuid.lib ole32.lib oleaut32.lib uuid.lib ^
  /out:h264_codec_test.exe
if errorlevel 1 exit /b 1
h264_codec_test.exe
