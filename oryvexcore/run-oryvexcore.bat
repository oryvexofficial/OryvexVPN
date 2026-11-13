@echo off
setlocal

cd /d "%~dp0"

echo Starting OryvexCore...
echo Press Ctrl+C to stop, or just close this window.
echo.

oryvexcore.exe %*

echo.
echo OryvexCore exited (exit code %errorlevel%).
echo This window stays open so you can read any errors above.
pause
