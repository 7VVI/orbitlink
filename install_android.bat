@echo off
setlocal
set "APK=%~dp0mobile\build\app\outputs\flutter-apk\app-release.apk"
set "ADB=adb"
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not exist "%APK%" (
  echo APK not found. Run build_android.bat first.
  pause
  exit /b 1
)
"%ADB%" install -r "%APK%"
if errorlevel 1 goto fail
"%ADB%" shell am start -n com.orbitlink.remote/.MainActivity
pause
exit /b 0
:fail
echo Android install/start failed. Check that a device is connected with "adb devices".
pause
exit /b 1
