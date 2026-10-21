@echo off
setlocal
cd /d "%~dp0mobile"
call flutter pub get
if errorlevel 1 goto fail
call flutter build apk --release
if errorlevel 1 goto fail
echo.
echo APK built: %CD%\build\app\outputs\flutter-apk\app-release.apk
pause
exit /b 0
:fail
echo Android build failed.
pause
exit /b 1
