@echo off
setlocal
cd /d "%~dp0server"
if exist "build\orbitlink-relay.exe" (
  echo Starting OrbitLink relay on port 7080 ...
  "build\orbitlink-relay.exe" %*
) else (
  echo Compiled relay not found, falling back to dart run ...
  dart run bin\server.dart %*
)
pause
