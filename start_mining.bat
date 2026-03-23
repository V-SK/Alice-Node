@echo off
setlocal

echo ========================================
echo   Alice Protocol Miner
echo ========================================
echo.

if not exist ".venv\Scripts\activate.bat" (
    echo Virtual environment not found. Run install.bat first.
    pause
    exit /b 1
)

call .venv\Scripts\activate.bat

REM Check for wallet password env var for unattended mode
if defined ALICE_WALLET_PASSWORD (
    echo Running in unattended mode...
)

REM Detect device
set DEVICE=cpu
nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    set DEVICE=cuda
)

echo Starting miner on %DEVICE%...
echo.

python alice_miner.py --ps-url https://ps.aliceprotocol.org --device %DEVICE% --allow-insecure

pause
