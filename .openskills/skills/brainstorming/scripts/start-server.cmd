@echo off
setlocal enabledelayedexpansion

REM Start the brainstorm server and output connection info
REM Usage: start-server.cmd [--project-dir <path>] [--host <bind-host>] [--url-host <display-host>]
REM
REM Starts server on a random high port, outputs JSON with URL.
REM Each session gets its own directory to avoid conflicts.
REM
REM Options:
REM   --project-dir <path>  Store session files under <path>\.superpowers\brainstorm\
REM   --host <bind-host>    Host/interface to bind (default: 127.0.0.1)
REM   --url-host <host>     Hostname shown in returned URL JSON

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR="
set "BIND_HOST=127.0.0.1"
set "URL_HOST="

:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--project-dir" (
    set "PROJECT_DIR=%~2"
    shift
    shift
    goto parse_args
)
if "%~1"=="--host" (
    set "BIND_HOST=%~2"
    shift
    shift
    goto parse_args
)
if "%~1"=="--url-host" (
    set "URL_HOST=%~2"
    shift
    shift
    goto parse_args
)
echo {"error": "Unknown argument: %~1"}
exit /b 1

:done_args

if "%URL_HOST%"=="" (
    if "%BIND_HOST%"=="127.0.0.1" (
        set "URL_HOST=localhost"
    ) else if "%BIND_HOST%"=="localhost" (
        set "URL_HOST=localhost"
    ) else (
        set "URL_HOST=%BIND_HOST%"
    )
)

REM Generate unique session ID using PID and timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value 2^>nul ^| find "="') do set "TIMESTAMP=%%I"
set "SESSION_ID=%RANDOM%-%TIMESTAMP:~0,14%"

if not "%PROJECT_DIR%"=="" (
    set "SCREEN_DIR=%PROJECT_DIR%\.superpowers\brainstorm\%SESSION_ID%"
) else (
    set "SCREEN_DIR=%TEMP%\brainstorm-%SESSION_ID%"
)

set "PID_FILE=%SCREEN_DIR%\.server.pid"
set "LOG_FILE=%SCREEN_DIR%\.server.log"

if not exist "%SCREEN_DIR%" mkdir "%SCREEN_DIR%"

REM Kill any existing server
if exist "%PID_FILE%" (
    set /p OLD_PID=<"%PID_FILE%"
    taskkill /PID !OLD_PID! /F >nul 2>&1
    del "%PID_FILE%" >nul 2>&1
)

cd /d "%SCRIPT_DIR%"

REM Windows runs in foreground mode (no nohup/disown equivalent needed for agent use)
set "BRAINSTORM_DIR=%SCREEN_DIR%"
set "BRAINSTORM_HOST=%BIND_HOST%"
set "BRAINSTORM_URL_HOST=%URL_HOST%"
set "BRAINSTORM_OWNER_PID="

REM Start server - foreground mode (agent will use background parameter if needed)
node server.cjs
exit /b %ERRORLEVEL%
