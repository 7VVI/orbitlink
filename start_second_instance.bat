@echo off
setlocal
rem Starts a second client with an isolated identity, for testing a remote
rem session on one machine. The cursor will chase itself - use two machines
rem for a realistic test.
set "ROOT=%~dp0"
set "ORBITLINK_DATA_DIR=%ROOT%.data\instance2"
if exist "%ROOT%app\build\windows\x64\runner\Release\orbitlink.exe" (
  start "" /d "%ROOT%app\build\windows\x64\runner\Release" "%ROOT%app\build\windows\x64\runner\Release\orbitlink.exe"
) else if exist "%ROOT%app\build\windows\x64\runner\Debug\orbitlink.exe" (
  start "" /d "%ROOT%app\build\windows\x64\runner\Debug" "%ROOT%app\build\windows\x64\runner\Debug\orbitlink.exe"
) else (
  echo No build found. Run: cd app ^&^& flutter build windows --release
  pause
)
