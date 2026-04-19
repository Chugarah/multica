@echo off
REM Self-elevating wrapper for Multica deploy actions.
REM Double-click to run Install + Register-Tasks with UAC prompt, preserving
REM the console window so the operator can read output.
REM
REM Matches the pattern used in D:\Projects\Hetzner\SSH\Core\*\deploy.cmd.

setlocal
cd /d "%~dp0"

REM Check elevation. If not admin, re-launch elevated via PowerShell.
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo === Multica deploy (elevated) ===
echo Repo root: %~dp0..\..
echo.

where pwsh >nul 2>&1
if %errorLevel% equ 0 (
    set PS=pwsh
) else (
    set PS=powershell
)

%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Multica.ps1"
if %errorLevel% neq 0 (
    echo Install-Multica.ps1 exited with %errorLevel%.
    pause
    exit /b %errorLevel%
)

echo.
choice /M "Register auto-start + nightly backup Scheduled Tasks now"
if %errorLevel% equ 1 (
    %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-Tasks.ps1"
)

echo.
choice /M "Start the stack now"
if %errorLevel% equ 1 (
    %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Multica.ps1"
)

echo.
echo Done. Press any key to close this window.
pause >nul
