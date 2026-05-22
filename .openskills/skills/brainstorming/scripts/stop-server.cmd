@echo off
setlocal enabledelayedexpansion

REM Stop the brainstorm server and clean up
REM Usage: stop-server.cmd <screen_dir>
REM
REM Kills the server process. Only deletes session directory if it's
REM under %%TEMP%%. Persistent directories (.superpowers\) are kept.

set "SCREEN_DIR=%~1"

if "%SCREEN_DIR%"=="" (
    echo {"error": "Usage: stop-server.cmd <screen_dir>"}
    exit /b 1
)

set "PID_FILE=%SCREEN_DIR%\.server.pid"

if not exist "%PID_FILE%" (
    echo {"status": "not_running"}
    exit /b 0
)

set /p PID=<"%PID_FILE%"

REM Try graceful shutdown
taskkill /PID %PID% >nul 2>&1

REM Wait for process to exit (up to ~2s)
set "RETRIES=0"
:wait_loop
if %RETRIES% GEQ 20 goto force_kill
timeout /t 0 /nobreak >nul 2>&1
tasklist /FI "PID eq %PID%" 2>nul | find "%PID%" >nul 2>&1
if errorlevel 1 goto process_dead
set /a RETRIES+=1
goto wait_loop

:force_kill
taskkill /PID %PID% /F >nul 2>&1
timeout /t 1 /nobreak >nul 2>&1

tasklist /FI "PID eq %PID%" 2>nul | find "%PID%" >nul 2>&1
if not errorlevel 1 (
    echo {"status": "failed", "error": "process still running"}
    exit /b 1
)

:process_dead
del "%PID_FILE%" >nul 2>&1
if exist "%SCREEN_DIR%\.server.log" del "%SCREEN_DIR%\.server.log" >nul 2>&1

REM Only delete ephemeral temp directories
echo %SCREEN_DIR% | find "%TEMP%" >nul 2>&1
if not errorlevel 1 (
    rmdir /s /q "%SCREEN_DIR%" >nul 2>&1
)

echo {"status": "stopped"}
exit /b 0
