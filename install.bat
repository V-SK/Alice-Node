@echo off
setlocal enabledelayedexpansion

echo ========================================
echo   Alice Protocol Miner - Installer
echo ========================================
echo.

REM Step 1: Find Python 3.10+
set PYTHON_BIN=
for %%P in (python3 python py) do (
    where %%P >nul 2>&1 && (
        for /f "tokens=*" %%V in ('%%P -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2^>nul') do (
            for /f "tokens=1,2 delims=." %%A in ("%%V") do (
                if %%A GEQ 3 if %%B GEQ 10 (
                    set PYTHON_BIN=%%P
                    echo [1/4] Python: %%P ^(%%V^)
                    goto :found_python
                )
            )
        )
    )
)
echo Python 3.10+ not found.
echo Download from: https://python.org/downloads/
echo IMPORTANT: Check "Add Python to PATH" during installation!
pause
exit /b 1

:found_python

REM Step 2: Create venv
if not exist ".venv" (
    echo [2/4] Creating virtual environment...
    %PYTHON_BIN% -m venv .venv
) else (
    echo [2/4] Virtual environment exists
)
call .venv\Scripts\activate.bat

REM Step 3: Detect GPU and install PyTorch
echo [3/4] Installing PyTorch...
nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    echo   NVIDIA GPU detected, installing CUDA version...
    pip install --upgrade torch --index-url https://download.pytorch.org/whl/cu124 -q
) else (
    echo   No NVIDIA GPU, installing CPU version...
    pip install --upgrade torch --index-url https://download.pytorch.org/whl/cpu -q
)

REM Install dependencies
if exist "requirements.txt" (
    pip install -r requirements.txt -q
)

REM Step 4: Verify
echo [4/4] Verifying installation...
echo.
%PYTHON_BIN% -c "import torch; d='CUDA ('+torch.cuda.get_device_name(0)+')' if torch.cuda.is_available() else 'CPU'; m=str(round(torch.cuda.get_device_properties(0).total_mem/1e9,1))+' GB' if torch.cuda.is_available() else 'N/A'; print(f'  PyTorch: {torch.__version__}'); print(f'  Device:  {d}'); print(f'  Memory:  {m}')"
echo.
echo Installation complete!
echo.
echo To start mining: start_mining.bat
pause
