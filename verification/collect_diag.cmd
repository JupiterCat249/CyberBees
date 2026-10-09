@echo off
rem ===========================================================================
rem  ONE-CLICK diagnostic collector  (double-click this file)
rem  Collects the diagnostics that the game auto-wrote on THIS machine and
rem  puts a zip on your Desktop.
rem  ASCII-only on purpose (Windows cmd + PowerShell 5.1 encoding safety).
rem ===========================================================================
setlocal
echo.
echo ===============================================
echo   Diag collector - one click
echo ===============================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_diag.ps1"
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
  echo [DONE] Look for the folder "diag-export" on your Desktop.
  echo        Send that folder ^(or the .zip inside^) back.
) else (
  echo [FAILED] rc=%RC%
  echo   - "diag dir not found" means the game was not run yet on this code.
  echo   - Otherwise: make sure your repo is at commit 07ec245 or newer.
)
echo.
pause
