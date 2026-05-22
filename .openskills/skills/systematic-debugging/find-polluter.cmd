@echo off
setlocal enabledelayedexpansion

REM Bisection script to find which test creates unwanted files/state
REM Usage: find-polluter.cmd <file_or_dir_to_check> <test_pattern>
REM Example: find-polluter.cmd ".git" "src\**\*.test.ts"

if "%~2"=="" (
    echo Usage: %~0 ^<file_to_check^> ^<test_pattern^>
    echo Example: %~0 ".git" "src\**\*.test.ts"
    exit /b 1
)

set "POLLUTION_CHECK=%~1"
set "TEST_PATTERN=%~2"

echo Searching for test that creates: %POLLUTION_CHECK%
echo Test pattern: %TEST_PATTERN%
echo.

set COUNT=0
set TOTAL=0

for /r %%F in (%TEST_PATTERN%) do (
    set /a TOTAL+=1
)

echo Found %TOTAL% test files
echo.

for /r %%F in (%TEST_PATTERN%) do (
    set /a COUNT+=1

    if exist "%POLLUTION_CHECK%" (
        echo WARNING: Pollution already exists before test !COUNT!/%TOTAL%
        echo    Skipping: %%F
    ) else (
        echo [!COUNT!/%TOTAL%] Testing: %%F

        npm test "%%F" >nul 2>&1

        if exist "%POLLUTION_CHECK%" (
            echo.
            echo FOUND POLLUTER!
            echo    Test: %%F
            echo    Created: %POLLUTION_CHECK%
            echo.
            echo Pollution details:
            dir "%POLLUTION_CHECK%"
            echo.
            echo To investigate:
            echo   npm test %%F
            exit /b 1
        )
    )
)

echo.
echo No polluter found - all tests clean!
exit /b 0
