@echo off
REM Run all unit tests — backend (Zig) + frontend (vitest)
setlocal
set ROOT=%~dp0
set PASS=0
set FAIL=0

echo ================================================
echo   ops_vpn test suite
echo ================================================
echo.

REM ---- Backend: Zig unit tests ----
echo [ Backend - Zig ]
cd /d "%ROOT%backend"
zig build test
if %ERRORLEVEL% EQU 0 (
    echo   OK All Zig tests passed
    set /a PASS+=1
) else (
    echo   FAIL Zig tests FAILED
    set /a FAIL+=1
)

echo.

REM ---- Frontend: vitest ----
echo [ Frontend - vitest ]
cd /d "%ROOT%frontend"
call yarn test --reporter=verbose
if %ERRORLEVEL% EQU 0 (
    echo   OK All frontend tests passed
    set /a PASS+=1
) else (
    echo   FAIL Frontend tests FAILED
    set /a FAIL+=1
)

echo.
echo ================================================
if %FAIL% EQU 0 (
    echo   All test suites passed
    echo ================================================
    exit /b 0
) else (
    echo   %FAIL% suite(s) failed
    echo ================================================
    exit /b 1
)
