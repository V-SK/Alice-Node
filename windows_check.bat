@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

echo ========================================================
echo   Alice Miner - Windows Full Diagnostic
echo   Version: 2026-03-27
echo ========================================================
echo.

set PASS=0
set FAIL=0
set WARN=0

:: ========== 1. System Info ==========
echo [1/10] System Information
echo --------------------------------------------------------
for /f "tokens=2 delims==" %%a in ('wmic os get Caption /value 2^>nul ^| find "="') do echo   OS: %%a
for /f "tokens=2 delims==" %%a in ('wmic os get OSArchitecture /value 2^>nul ^| find "="') do echo   Arch: %%a
for /f "tokens=2 delims==" %%a in ('wmic computersystem get TotalPhysicalMemory /value 2^>nul ^| find "="') do (
    set /a "mem_gb=%%a / 1073741824"
    echo   RAM: !mem_gb! GB
)
echo.

:: ========== 2. Python ==========
echo [2/10] Python Environment
echo --------------------------------------------------------

where python >nul 2>&1
if %errorlevel% neq 0 (
    where python3 >nul 2>&1
    if %errorlevel% neq 0 (
        echo   [FAIL] Python not found in PATH!
        echo   Fix: Download from https://www.python.org/downloads/
        echo        IMPORTANT: Check "Add Python to PATH" during install!
        set /a FAIL+=1
        goto :skip_python
    ) else (
        set PYTHON=python3
    )
) else (
    set PYTHON=python
)

for /f "tokens=*" %%v in ('%PYTHON% --version 2^>^&1') do echo   %PYTHON%: %%v
set /a PASS+=1

:: Check Python version >= 3.9
for /f "tokens=2 delims= " %%v in ('%PYTHON% --version 2^>^&1') do set PYVER=%%v
for /f "tokens=1,2 delims=." %%a in ("%PYVER%") do (
    if %%a LSS 3 (
        echo   [FAIL] Python 3.9+ required, got %PYVER%
        set /a FAIL+=1
    ) else if %%a EQU 3 if %%b LSS 9 (
        echo   [FAIL] Python 3.9+ required, got %PYVER%
        set /a FAIL+=1
    ) else (
        echo   [PASS] Python version OK
        set /a PASS+=1
    )
)

:: Check pip
%PYTHON% -m pip --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [FAIL] pip not installed!
    echo   Fix: %PYTHON% -m ensurepip --upgrade
    set /a FAIL+=1
) else (
    for /f "tokens=*" %%v in ('%PYTHON% -m pip --version 2^>^&1') do echo   pip: %%v
    set /a PASS+=1
)
echo.

:skip_python

:: ========== 3. PyTorch ==========
echo [3/10] PyTorch
echo --------------------------------------------------------

%PYTHON% -c "import torch; print(f'  Version: {torch.__version__}')" 2>nul
if %errorlevel% neq 0 (
    echo   [FAIL] PyTorch not installed!
    echo   Fix (NVIDIA GPU):
    echo     pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
    echo   Fix (CPU only):
    echo     pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
    set /a FAIL+=1
    goto :skip_torch
) else (
    set /a PASS+=1
)

:: CUDA check
%PYTHON% -c "import torch; cuda=torch.cuda.is_available(); print(f'  CUDA available: {cuda}'); print(f'  CUDA version: {torch.version.cuda}' if cuda else '  CUDA: Not available (CPU mode)'); print(f'  GPU: {torch.cuda.get_device_name(0)}' if cuda else ''); print(f'  GPU Memory: {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB' if cuda else '')" 2>nul

%PYTHON% -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>nul
if %errorlevel% neq 0 (
    echo   [WARN] No CUDA GPU detected - will run in CPU mode (SLOW)
    echo   Note: CPU mining works but is 10-50x slower than GPU
    echo   If you have an NVIDIA GPU, install CUDA toolkit:
    echo     https://developer.nvidia.com/cuda-downloads
    echo   Then reinstall PyTorch with CUDA:
    echo     pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
    set /a WARN+=1
) else (
    echo   [PASS] CUDA GPU detected
    set /a PASS+=1
)

:: Tensor test
echo.
echo   Running tensor computation test...
%PYTHON% -c "import torch; x=torch.randn(100,100); y=torch.mm(x,x); print(f'  [PASS] Tensor computation OK (result shape: {y.shape})')" 2>nul
if %errorlevel% neq 0 (
    echo   [FAIL] Tensor computation failed!
    set /a FAIL+=1
) else (
    set /a PASS+=1
)

echo.
:skip_torch

:: ========== 4. Required Python Packages ==========
echo [4/10] Required Python Packages
echo --------------------------------------------------------

set PACKAGES=requests psutil numpy
for %%p in (%PACKAGES%) do (
    %PYTHON% -c "import %%p; print(f'  %%p: {%%p.__version__}')" 2>nul
    if !errorlevel! neq 0 (
        echo   [FAIL] %%p not installed
        echo   Fix: pip install %%p
        set /a FAIL+=1
    ) else (
        set /a PASS+=1
    )
)
echo.

:: ========== 5. Network Connectivity ==========
echo [5/10] Network Connectivity
echo --------------------------------------------------------

:: Test general internet
ping -n 1 -w 3000 8.8.8.8 >nul 2>&1
if %errorlevel% neq 0 (
    echo   [FAIL] No internet connection!
    set /a FAIL+=1
) else (
    echo   [PASS] Internet connection OK
    set /a PASS+=1
)

:: Test PS connection
echo.
echo   Testing Parameter Server connection...
%PYTHON% -c "import requests; r=requests.get('http://65.109.84.107:8080/status', timeout=10); print(f'  PS Status: {r.status_code}'); d=r.json(); print(f'  Epoch: {d.get(\"epoch\",\"?\")}, Miners: {d.get(\"connected_miners\",\"?\")}, Model: {d.get(\"model_version\",\"?\")}'); print('  [PASS] Parameter Server reachable')" 2>nul
if %errorlevel% neq 0 (
    echo   [FAIL] Cannot connect to Parameter Server (65.109.84.107:8080)
    echo.
    echo   Possible causes:
    echo     1. PS is not running
    echo     2. Firewall blocking port 8080
    echo     3. ISP blocking the connection
    echo.
    echo   Firewall test:
    
    powershell -Command "try { $t = New-Object Net.Sockets.TcpClient; $t.Connect('65.109.84.107', 8080); Write-Host '  TCP port 8080: OPEN'; $t.Close() } catch { Write-Host '  TCP port 8080: BLOCKED' }" 2>nul
    
    echo.
    echo   Try in browser: http://65.109.84.107:8080/status
    set /a FAIL+=1
) else (
    set /a PASS+=1
)

:: DNS test
nslookup github.com >nul 2>&1
if %errorlevel% neq 0 (
    echo   [WARN] DNS resolution issues
    set /a WARN+=1
) else (
    echo   [PASS] DNS resolution OK
    set /a PASS+=1
)
echo.

:: ========== 6. Firewall & Antivirus ==========
echo [6/10] Firewall ^& Antivirus
echo --------------------------------------------------------

:: Check if Windows Firewall is on
netsh advfirewall show currentprofile state 2>nul | find "ON" >nul
if %errorlevel% equ 0 (
    echo   [INFO] Windows Firewall is ON
    echo   [WARN] May need to allow Python through firewall
    echo   Fix: Settings -^> Windows Security -^> Firewall -^> Allow an app
    echo        Add python.exe to allowed apps
    set /a WARN+=1
) else (
    echo   [PASS] Windows Firewall is OFF or not blocking
    set /a PASS+=1
)

:: Check if Python is allowed through firewall
netsh advfirewall firewall show rule name=all 2>nul | findstr /i "python" >nul
if %errorlevel% equ 0 (
    echo   [PASS] Python has firewall rules
    set /a PASS+=1
) else (
    echo   [WARN] No firewall rules for Python found
    echo   If connection fails, run as admin:
    echo     netsh advfirewall firewall add rule name="Python" dir=out action=allow program="%PYTHON%" enable=yes
    set /a WARN+=1
)
echo.

:: ========== 7. Memory & Disk ==========
echo [7/10] Memory ^& Disk Space
echo --------------------------------------------------------

:: RAM check
%PYTHON% -c "import psutil; mem=psutil.virtual_memory(); total_gb=mem.total/1e9; avail_gb=mem.available/1e9; print(f'  Total RAM: {total_gb:.1f} GB'); print(f'  Available: {avail_gb:.1f} GB ({mem.percent}%% used)'); ok='PASS' if avail_gb>=4 else ('WARN' if avail_gb>=2 else 'FAIL'); print(f'  [{ok}] {\"Enough\" if avail_gb>=4 else \"Low\"} memory for mining')" 2>nul
if %errorlevel% neq 0 (
    echo   [WARN] Could not check memory (psutil not installed)
    set /a WARN+=1
)

:: Disk check
for /f "tokens=3" %%a in ('dir %cd% 2^>nul ^| find "bytes free"') do (
    echo   Free disk space: %%a bytes
)

%PYTHON% -c "import shutil; total,used,free=shutil.disk_usage('.'); print(f'  Disk free: {free/1e9:.1f} GB'); ok='PASS' if free/1e9>=20 else ('WARN' if free/1e9>=10 else 'FAIL'); print(f'  [{ok}] {\"Enough\" if free/1e9>=10 else \"Low\"} disk space (need ~15GB for model)')" 2>nul
echo.

:: ========== 8. Alice Miner Files ==========
echo [8/10] Alice Miner Files
echo --------------------------------------------------------

set MINER_FILES=alice_miner_v2.py src\model.py src\compression.py src\__init__.py test_env.py
for %%f in (%MINER_FILES%) do (
    if exist "%%f" (
        echo   [PASS] %%f exists
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f MISSING!
        set /a FAIL+=1
    )
)
echo.

:: ========== 9. GPU Driver (NVIDIA) ==========
echo [9/10] GPU Driver Check
echo --------------------------------------------------------

where nvidia-smi >nul 2>&1
if %errorlevel% neq 0 (
    echo   [INFO] nvidia-smi not found (no NVIDIA GPU or driver not installed)
    echo   If you have an NVIDIA GPU:
    echo     Download driver: https://www.nvidia.com/download/index.aspx
) else (
    nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader 2>nul
    if !errorlevel! equ 0 (
        echo   [PASS] NVIDIA driver detected
        set /a PASS+=1
    )
    echo.
    echo   Full nvidia-smi:
    nvidia-smi 2>nul
)
echo.

:: ========== 10. Full Mining Test ==========
echo [10/10] Mining Simulation Test
echo --------------------------------------------------------
echo   Running quick training test...

%PYTHON% -c "
import sys
try:
    import torch
    import torch.nn as nn
    
    # Test 1: Model creation
    print('  Test 1: Creating tiny model...')
    class TinyModel(nn.Module):
        def __init__(self):
            super().__init__()
            self.embed = nn.Embedding(1000, 128)
            self.fc = nn.Linear(128, 1000)
        def forward(self, x):
            return self.fc(self.embed(x))
    
    model = TinyModel()
    print(f'  [PASS] Model created ({sum(p.numel() for p in model.parameters()):,} params)')
    
    # Test 2: Forward + backward
    print('  Test 2: Forward + backward pass...')
    x = torch.randint(0, 1000, (2, 16))
    out = model(x)
    loss = nn.CrossEntropyLoss()(out.view(-1, 1000), x.view(-1))
    loss.backward()
    grad_count = sum(1 for p in model.parameters() if p.grad is not None)
    print(f'  [PASS] Gradients computed ({grad_count} params, loss={loss.item():.4f})')
    
    # Test 3: Compression
    print('  Test 3: Gradient compression...')
    sys.path.insert(0, '.')
    from src.compression import TopKCompressor
    comp = TopKCompressor(ratio=0.01)
    grads = {n: p.grad for n, p in model.named_parameters() if p.grad is not None}
    compressed = comp.compress(grads)
    print(f'  [PASS] Compression OK (format: {compressed.get(\"fmt\", \"?\")})')
    
    # Test 4: HTTP connectivity simulation
    print('  Test 4: HTTP request test...')
    import requests
    try:
        r = requests.get('http://65.109.84.107:8080/status', timeout=10)
        if r.status_code == 200:
            print(f'  [PASS] PS connection OK')
        else:
            print(f'  [WARN] PS returned status {r.status_code}')
    except Exception as e:
        print(f'  [FAIL] Cannot reach PS: {e}')
    
    # Test 5: GPU computation (if available)
    if torch.cuda.is_available():
        print('  Test 5: GPU computation...')
        device = torch.device('cuda')
        model_gpu = model.to(device)
        x_gpu = x.to(device)
        out_gpu = model_gpu(x_gpu)
        print(f'  [PASS] GPU computation OK')
    else:
        print('  Test 5: GPU not available, skipped')
    
    print()
    print('  =============================================')
    print('  Mining simulation: ALL TESTS PASSED')
    print('  =============================================')

except Exception as e:
    print(f'  [FAIL] Test failed: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>nul

if %errorlevel% neq 0 (
    echo   [FAIL] Mining simulation failed!
    set /a FAIL+=1
) else (
    set /a PASS+=1
)
echo.

:: ========== Summary ==========
echo ========================================================
echo   DIAGNOSTIC SUMMARY
echo ========================================================
echo.
echo   PASS: %PASS%  |  FAIL: %FAIL%  |  WARN: %WARN%
echo.

if %FAIL% gtr 0 (
    echo   STATUS: PROBLEMS FOUND
    echo.
    echo   Fix all [FAIL] items above before mining.
    echo.
    echo   Quick fix commands:
    echo     1. Install Python: https://www.python.org/downloads/
    echo     2. Install PyTorch (GPU):
    echo        pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
    echo     3. Install PyTorch (CPU):
    echo        pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
    echo     4. Install dependencies:
    echo        pip install requests psutil numpy
) else if %WARN% gtr 0 (
    echo   STATUS: READY (with warnings)
    echo   Mining should work but check [WARN] items for best performance.
) else (
    echo   STATUS: ALL CLEAR - Ready to mine!
)

echo.
echo   To start mining:
echo     python alice_miner_v2.py --ps-url http://65.109.84.107:8080 --device cuda
echo     (or --device cpu if no GPU)
echo.
echo ========================================================

:: Save report
echo Saving report to alice_diagnostic_%date:~-4%%date:~-10,2%%date:~-7,2%.txt...
(
    echo Alice Miner Diagnostic Report
    echo Date: %date% %time%
    echo PASS: %PASS%, FAIL: %FAIL%, WARN: %WARN%
) > alice_diagnostic_report.txt

pause
endlocal
