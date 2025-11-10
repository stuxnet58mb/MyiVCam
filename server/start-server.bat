@echo off
cd /d "%~dp0"
if not exist "node_modules" (
  echo Installing npm dependencies...
  npm install
)
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4" ^| findstr /v "169.254"') do set IP=%%a
set IP=%IP: =%
echo Server starting on http://%IP%:3000
node server.js
pause