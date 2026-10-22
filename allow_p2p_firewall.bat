@echo off
setlocal
rem Allows OrbitLink to receive direct P2P connections on trusted LANs.
rem Run this script as Administrator on the controlled (host) PC.

set "APP=%~dp0app\orbitlink.exe"
if not exist "%APP%" set "APP=%~dp0app\build\windows\x64\runner\Release\orbitlink.exe"

net session >nul 2>&1
if errorlevel 1 (
  echo Please right-click this file and choose "Run as administrator".
  echo 请右键此文件，选择“以管理员身份运行”。
  pause
  exit /b 1
)

if not exist "%APP%" (
  echo orbitlink.exe not found. Keep this script next to the app folder.
  echo 未找到 orbitlink.exe，请把脚本放在应用目录旁。
  pause
  exit /b 1
)

netsh advfirewall firewall delete rule name="OrbitLink P2P" >nul 2>&1
netsh advfirewall firewall add rule name="OrbitLink P2P" dir=in action=allow program="%APP%" enable=yes profile=private,domain protocol=any
if errorlevel 1 (
  echo Failed to add the firewall rule.
  echo 添加防火墙规则失败。
) else (
  echo OrbitLink P2P inbound rule added for Private and Domain networks.
  echo 已允许 OrbitLink 在“专用网络”和“域网络”接收局域网直连。
  echo If P2P still shows relay, set the network profile to Private.
  echo 如果仍显示中继，请把当前网络设为“专用网络”。
)
pause
