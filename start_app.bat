@echo off
setlocal
set "ROOT=%~dp0"
if exist "%ROOT%app\build\windows\x64\runner\Release\orbitlink.exe" (
  start "" /d "%ROOT%app\build\windows\x64\runner\Release" "%ROOT%app\build\windows\x64\runner\Release\orbitlink.exe"
) else if exist "%ROOT%app\build\windows\x64\runner\Debug\orbitlink.exe" (
  start "" /d "%ROOT%app\build\windows\x64\runner\Debug" "%ROOT%app\build\windows\x64\runner\Debug\orbitlink.exe"
) else (
  echo No build found. Run: cd app ^&^& flutter build windows --release
  pause
)
