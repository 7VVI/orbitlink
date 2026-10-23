@echo off
setlocal
cd /d "%~dp0server"
if exist "build\orbitlink-signaling-webrtc.exe" (
  echo Starting OrbitLink WebRTC signaling on port 7080 ...
  "build\orbitlink-signaling-webrtc.exe" %*
) else (
  echo Compiled signaling server not found, falling back to dart run ...
  dart run bin\server.dart %*
)
pause
