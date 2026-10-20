@echo off
setlocal
cd /d "%~dp0"
where node.exe >nul 2>nul
if errorlevel 1 (
  echo Node.js was not found. Run server.mjs using your existing node.exe.
  pause
  exit /b 1
)
echo ShakeHero Wi-Fi Sensor Lab: http://localhost:8787/?mode=receiver
echo The phone needs the local CA certificate on first connection.
echo Keep this window open. Press Ctrl+C to stop.
node.exe server.mjs --wifi --game --port 8787 --wifi-port 8788 --open
pause
