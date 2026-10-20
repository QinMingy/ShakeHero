@echo off
setlocal
cd /d "%~dp0"
where node.exe >nul 2>nul
if errorlevel 1 (
  echo Node.js was not found. Install Node.js or run server.mjs with your existing node.exe.
  pause
  exit /b 1
)
echo ShakeHero Sensor Lab: http://localhost:8787/
echo Keep this window open. Press Ctrl+C to stop.
node.exe server.mjs --port 8787 --open
pause
