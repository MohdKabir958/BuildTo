@echo off
echo ===================================================
echo   Starting Buildto Client Demo Prototype Server
echo ===================================================
start "" "http://localhost:8080"
node "%~dp0server.mjs"
pause
