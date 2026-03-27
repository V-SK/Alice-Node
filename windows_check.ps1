# Alice Miner - Windows Full Diagnostic (PowerShell)
# Run: powershell -ExecutionPolicy Bypass -File windows_check.ps1

$ErrorActionPreference = "Continue"
$pass = 0; $fail = 0; $warn = 0
$report = @()

function Log-Pass($msg) { 
    Write-Host "  [PASS] $msg" -ForegroundColor Green
    $script:pass++
    $script:report += "[PASS] $msg"
}
function Log-Fail($msg) { 
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
    $script:fail++
    $script:report += "[FAIL] $msg"
}
function Log-Warn($msg) { 
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
    $script:warn++
    $script:report += "[WARN] $msg"
}
function Log-Info($msg) { 
    Write-Host "  [INFO] $msg" -ForegroundColor Cyan
    $script:report += "[INFO] $msg"
}
function Log-Fix($msg) { 
    Write-Host "         Fix: $msg" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Alice Miner - Windows Full Diagnostic" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# ===== 1. System Info =====
Write-Host "[1/11] System Information" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)

Write-Host "  OS: $($os.Caption) ($($os.OSArchitecture))"
Write-Host "  Build: $($os.BuildNumber)"
Write-Host "  RAM: ${totalRAM} GB"
Write-Host "  CPU: $($cs.NumberOfProcessors) socket(s), $($cs.NumberOfLogicalProcessors) logical cores"
Write-Host ""

# ===== 2. Python =====
Write-Host "[2/11] Python Environment" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python \d") {
            $pythonCmd = $cmd
            break
        }
    } catch {}
}

if (-not $pythonCmd) {
    Log-Fail "Python not found in PATH!"
    Log-Fix "Download from https://www.python.org/downloads/"
    Write-Host "         IMPORTANT: Check 'Add Python to PATH' during install!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Cannot continue without Python. Fix this first!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$pyVersion = & $pythonCmd --version 2>&1
Write-Host "  Python: $pyVersion"
Write-Host "  Path: $(Get-Command $pythonCmd | Select-Object -ExpandProperty Source)"

# Version check
$verMatch = [regex]::Match("$pyVersion", "(\d+)\.(\d+)")
$pyMajor = [int]$verMatch.Groups[1].Value
$pyMinor = [int]$verMatch.Groups[2].Value

if ($pyMajor -ge 3 -and $pyMinor -ge 9) {
    Log-Pass "Python version OK ($pyMajor.$pyMinor >= 3.9)"
} else {
    Log-Fail "Python 3.9+ required, got $pyMajor.$pyMinor"
    Log-Fix "Download Python 3.11+ from https://www.python.org/downloads/"
}

# pip check
try {
    $pipVer = & $pythonCmd -m pip --version 2>&1
    Write-Host "  pip: $pipVer"
    Log-Pass "pip available"
} catch {
    Log-Fail "pip not installed"
    Log-Fix "$pythonCmd -m ensurepip --upgrade"
}

# venv check
try {
    & $pythonCmd -c "import venv" 2>&1 | Out-Null
    Log-Pass "venv module available"
} catch {
    Log-Warn "venv module not available (optional but recommended)"
}
Write-Host ""

# ===== 3. PyTorch =====
Write-Host "[3/11] PyTorch" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$torchCheck = & $pythonCmd -c @"
import sys
try:
    import torch
    print(f'VERSION:{torch.__version__}')
    print(f'CUDA:{torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'CUDA_VER:{torch.version.cuda}')
        print(f'GPU_NAME:{torch.cuda.get_device_name(0)}')
        print(f'GPU_MEM:{torch.cuda.get_device_properties(0).total_mem / 1e9:.1f}')
        print(f'GPU_COUNT:{torch.cuda.device_count()}')
    print('OK')
except ImportError:
    print('NOT_INSTALLED')
except Exception as e:
    print(f'ERROR:{e}')
"@ 2>&1

if ("$torchCheck" -match "NOT_INSTALLED") {
    Log-Fail "PyTorch not installed!"
    Write-Host ""
    Write-Host "  Install PyTorch:" -ForegroundColor Yellow
    Write-Host "  For NVIDIA GPU (recommended):" -ForegroundColor Yellow
    Write-Host "    pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121" -ForegroundColor White
    Write-Host "  For CPU only:" -ForegroundColor Yellow
    Write-Host "    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu" -ForegroundColor White
    Write-Host ""
} else {
    foreach ($line in $torchCheck) {
        if ($line -match "^VERSION:(.+)") { 
            Write-Host "  PyTorch version: $($Matches[1])"
            Log-Pass "PyTorch installed ($($Matches[1]))"
        }
        if ($line -match "^CUDA:True") {
            Log-Pass "CUDA available"
        }
        if ($line -match "^CUDA:False") {
            Log-Warn "CUDA not available - will use CPU (slow)"
            Log-Fix "Install CUDA toolkit: https://developer.nvidia.com/cuda-downloads"
            Log-Fix "Then: pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121"
        }
        if ($line -match "^CUDA_VER:(.+)") { Write-Host "  CUDA version: $($Matches[1])" }
        if ($line -match "^GPU_NAME:(.+)") { Write-Host "  GPU: $($Matches[1])" }
        if ($line -match "^GPU_MEM:(.+)") { 
            $gpuMem = [float]$Matches[1]
            Write-Host "  GPU Memory: $gpuMem GB"
            if ($gpuMem -ge 8) {
                Log-Pass "GPU memory sufficient ($gpuMem GB >= 8 GB)"
            } elseif ($gpuMem -ge 4) {
                Log-Warn "GPU memory low ($gpuMem GB) - may need fewer layers"
            } else {
                Log-Warn "GPU memory very low ($gpuMem GB) - consider CPU mode"
            }
        }
        if ($line -match "^GPU_COUNT:(.+)") { Write-Host "  GPU count: $($Matches[1])" }
    }
}
Write-Host ""

# ===== 4. Required Packages =====
Write-Host "[4/11] Required Python Packages" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$packages = @("requests", "psutil", "numpy")
$missingPkgs = @()

foreach ($pkg in $packages) {
    $result = & $pythonCmd -c "import $pkg; print(f'{$pkg.__version__}')" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Log-Fail "$pkg not installed"
        $missingPkgs += $pkg
    } else {
        Write-Host "  $pkg : $result"
        Log-Pass "$pkg OK"
    }
}

if ($missingPkgs.Count -gt 0) {
    $pkgList = $missingPkgs -join " "
    Log-Fix "pip install $pkgList"
}
Write-Host ""

# ===== 5. Network =====
Write-Host "[5/11] Network Connectivity" -ForegroundColor White
Write-Host "--------------------------------------------------------"

# Internet
$ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
if ($ping) {
    Log-Pass "Internet connection OK"
} else {
    Log-Fail "No internet connection!"
}

# DNS
try {
    Resolve-DnsName github.com -ErrorAction Stop | Out-Null
    Log-Pass "DNS resolution OK"
} catch {
    Log-Fail "DNS resolution failed"
}

# PS Connection
Write-Host ""
Write-Host "  Testing Parameter Server..." -ForegroundColor Cyan

$psCheck = & $pythonCmd -c @"
import requests, json
try:
    r = requests.get('https://ps.aliceprotocol.org/status', timeout=15)
    if r.status_code == 200:
        d = r.json()
        print(f"STATUS:OK")
        print(f"EPOCH:{d.get('epoch', '?')}")
        print(f"MINERS:{d.get('connected_miners', '?')}")
        print(f"MODEL_VER:{d.get('model_version', '?')}")
    else:
        print(f"STATUS:HTTP_{r.status_code}")
except requests.exceptions.ConnectTimeout:
    print("STATUS:TIMEOUT")
except requests.exceptions.ConnectionError as e:
    print(f"STATUS:CONN_ERROR:{e}")
except Exception as e:
    print(f"STATUS:ERROR:{e}")
"@ 2>&1

$psOk = $false
foreach ($line in $psCheck) {
    if ($line -match "^STATUS:OK") { 
        $psOk = $true
        Log-Pass "Parameter Server reachable"
    }
    if ($line -match "^EPOCH:(.+)") { Write-Host "  PS Epoch: $($Matches[1])" }
    if ($line -match "^MINERS:(.+)") { Write-Host "  Connected Miners: $($Matches[1])" }
    if ($line -match "^MODEL_VER:(.+)") { Write-Host "  Model Version: $($Matches[1])" }
    if ($line -match "^STATUS:TIMEOUT") {
        Log-Fail "Connection to PS timed out (firewall?)"
    }
    if ($line -match "^STATUS:CONN_ERROR") {
        Log-Fail "Cannot connect to PS"
    }
    if ($line -match "^STATUS:ERROR:(.+)") {
        Log-Fail "PS error: $($Matches[1])"
    }
}

if (-not $psOk) {
    Write-Host ""
    Write-Host "  Diagnosing connection issue..." -ForegroundColor Yellow

    # TCP port test
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $tcp.Connect("ps.aliceprotocol.org", 443)
        Write-Host "  TCP port 8080: OPEN" -ForegroundColor Green
        $tcp.Close()
    } catch {
        Write-Host "  TCP port 8080: BLOCKED" -ForegroundColor Red
        Write-Host "  Possible causes:" -ForegroundColor Yellow
        Write-Host "    1. PS server is down" -ForegroundColor White
        Write-Host "    2. Your firewall blocks outbound port 8080" -ForegroundColor White
        Write-Host "    3. ISP or corporate network blocking" -ForegroundColor White
        Write-Host "    4. VPN/proxy interfering" -ForegroundColor White
    }

    # Traceroute (quick)
    Write-Host ""
    Write-Host "  Running traceroute (first 5 hops)..." -ForegroundColor Cyan
    tracert -d -h 5 ps.aliceprotocol.org 2>&1 | Select-Object -First 8 | ForEach-Object { Write-Host "  $_" }
}
Write-Host ""

# ===== 6. Firewall =====
Write-Host "[6/11] Firewall & Security" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$fwProfile = netsh advfirewall show currentprofile state 2>&1
if ("$fwProfile" -match "ON") {
    Log-Info "Windows Firewall is ON"
    
    # Check Python rules
    $fwRules = netsh advfirewall firewall show rule name=all 2>&1 | Select-String -Pattern "python" -SimpleMatch
    if ($fwRules) {
        Log-Pass "Python has firewall rules"
    } else {
        Log-Warn "No firewall rules for Python - may need to allow when prompted"
        Log-Fix "When Windows asks 'Allow Python to communicate', click Allow"
    }
} else {
    Log-Pass "Firewall not blocking"
}

# Antivirus check
$av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
if ($av) {
    foreach ($a in $av) {
        Log-Info "Antivirus: $($a.displayName)"
    }
    Log-Warn "Antivirus may interfere with mining - add Python to exclusions if needed"
} else {
    Log-Info "No third-party antivirus detected"
}
Write-Host ""

# ===== 7. Memory & Disk =====
Write-Host "[7/11] Memory & Disk Space" -ForegroundColor White
Write-Host "--------------------------------------------------------"

# RAM
$memCheck = & $pythonCmd -c @"
import psutil
mem = psutil.virtual_memory()
total = mem.total / 1e9
avail = mem.available / 1e9
used_pct = mem.percent
print(f'TOTAL:{total:.1f}')
print(f'AVAIL:{avail:.1f}')
print(f'USED:{used_pct}')
"@ 2>&1

foreach ($line in $memCheck) {
    if ($line -match "^TOTAL:(.+)") { Write-Host "  Total RAM: $($Matches[1]) GB" }
    if ($line -match "^AVAIL:(.+)") { 
        $availGB = [float]$Matches[1]
        Write-Host "  Available RAM: $availGB GB"
        if ($availGB -ge 8) {
            Log-Pass "Enough RAM for mining ($availGB GB free)"
        } elseif ($availGB -ge 4) {
            Log-Warn "RAM is tight ($availGB GB free) - close other apps while mining"
        } else {
            Log-Fail "Not enough RAM ($availGB GB free) - need at least 4 GB free"
        }
    }
    if ($line -match "^USED:(.+)") { Write-Host "  RAM used: $($Matches[1])%" }
}

# Disk
$disk = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -eq "$($pwd.Drive.Root)" }
$freeGB = [math]::Round($disk.Free / 1GB, 1)
Write-Host "  Disk free ($($disk.Root)): $freeGB GB"

if ($freeGB -ge 20) {
    Log-Pass "Enough disk space ($freeGB GB free)"
} elseif ($freeGB -ge 10) {
    Log-Warn "Disk space is tight ($freeGB GB free) - model needs ~15 GB"
} else {
    Log-Fail "Not enough disk space ($freeGB GB free) - need at least 15 GB"
}
Write-Host ""

# ===== 8. GPU Driver =====
Write-Host "[8/11] GPU Driver (NVIDIA)" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $smiOutput = nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,temperature.gpu,utilization.gpu --format=csv,noheader 2>&1
    if ($LASTEXITCODE -eq 0) {
        $parts = "$smiOutput".Split(",")
        Write-Host "  GPU: $($parts[0].Trim())"
        Write-Host "  Driver: $($parts[1].Trim())"
        Write-Host "  VRAM Total: $($parts[2].Trim())"
        Write-Host "  VRAM Free: $($parts[3].Trim())"
        Write-Host "  Temperature: $($parts[4].Trim()) C"
        Write-Host "  Utilization: $($parts[5].Trim())"
        Log-Pass "NVIDIA driver OK"
    }
} else {
    Log-Info "nvidia-smi not found"
    
    # Check for any GPU
    $gpus = Get-CimInstance Win32_VideoController
    foreach ($gpu in $gpus) {
        Write-Host "  Detected: $($gpu.Name)"
        if ($gpu.Name -match "NVIDIA") {
            Log-Warn "NVIDIA GPU detected but driver may not be installed"
            Log-Fix "Download driver: https://www.nvidia.com/download/index.aspx"
        } elseif ($gpu.Name -match "AMD|Radeon") {
            Log-Info "AMD GPU detected - not supported for CUDA, will use CPU"
        } elseif ($gpu.Name -match "Intel") {
            Log-Info "Intel GPU detected - will use CPU for mining"
        }
    }
}
Write-Host ""

# ===== 9. Miner Files =====
Write-Host "[9/11] Alice Miner Files" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$requiredFiles = @(
    "alice_node.py",
    "src/model.py",
    "src/compression.py",
    "src/__init__.py",
    "test_env.py"
)

$missingFiles = @()
foreach ($f in $requiredFiles) {
    if (Test-Path $f) {
        Log-Pass "$f exists"
    } else {
        Log-Fail "$f MISSING!"
        $missingFiles += $f
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "  Missing files! Make sure you:" -ForegroundColor Yellow
    Write-Host "    1. Cloned the full alice-project repository" -ForegroundColor White
    Write-Host "    2. Are running this script from the alice-project directory" -ForegroundColor White
    Write-Host "  Current directory: $pwd" -ForegroundColor White
}
Write-Host ""

# ===== 10. CUDA Compatibility =====
Write-Host "[10/11] CUDA / PyTorch Compatibility" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$cudaCompat = & $pythonCmd -c @"
import torch
import sys

# Check torch+CUDA match
if torch.cuda.is_available():
    torch_cuda = torch.version.cuda
    print(f'TORCH_CUDA:{torch_cuda}')
    
    # Test actual GPU computation
    try:
        x = torch.randn(100, 100, device='cuda')
        y = torch.mm(x, x)
        del x, y
        torch.cuda.empty_cache()
        print('GPU_COMPUTE:OK')
    except Exception as e:
        print(f'GPU_COMPUTE:FAIL:{e}')
    
    # Test FP16 (required for mining)
    try:
        x = torch.randn(100, 100, dtype=torch.float16, device='cuda')
        y = torch.mm(x, x)
        del x, y
        torch.cuda.empty_cache()
        print('FP16:OK')
    except Exception as e:
        print(f'FP16:FAIL:{e}')
else:
    print('NO_CUDA')
    # CPU FP16 test
    try:
        x = torch.randn(100, 100, dtype=torch.float16)
        y = torch.mm(x, x)
        print('FP16_CPU:OK')
    except:
        print('FP16_CPU:FAIL')
"@ 2>&1

foreach ($line in $cudaCompat) {
    if ($line -match "^TORCH_CUDA:(.+)") { Log-Info "PyTorch CUDA version: $($Matches[1])" }
    if ($line -match "^GPU_COMPUTE:OK") { Log-Pass "GPU computation verified" }
    if ($line -match "^GPU_COMPUTE:FAIL:(.+)") { Log-Fail "GPU computation failed: $($Matches[1])" }
    if ($line -match "^FP16:OK") { Log-Pass "FP16 (half precision) GPU OK" }
    if ($line -match "^FP16:FAIL") { Log-Fail "FP16 not supported on GPU" }
    if ($line -match "^NO_CUDA") { Log-Info "CUDA not available, testing CPU..." }
    if ($line -match "^FP16_CPU:OK") { Log-Pass "FP16 CPU computation OK" }
    if ($line -match "^FP16_CPU:FAIL") { Log-Warn "FP16 CPU issues - may affect performance" }
}
Write-Host ""

# ===== 11. Full Mining Simulation =====
Write-Host "[11/11] Full Mining Simulation" -ForegroundColor White
Write-Host "--------------------------------------------------------"

$simResult = & $pythonCmd -c @"
import sys, os, time
sys.path.insert(0, '.')

print('  Step 1: Import modules...')
try:
    import torch
    import torch.nn as nn
    import requests
    from src.model import AliceConfig, AliceForCausalLM
    from src.compression import TopKCompressor
    print('  [OK] All imports successful')
except ImportError as e:
    print(f'  [FAIL] Import error: {e}')
    sys.exit(1)

print('  Step 2: Create mini model (2 layers)...')
try:
    config = AliceConfig(
        num_layers=2,
        hidden_dim=256,
        intermediate_size=512,
        num_attention_heads=4,
        num_kv_heads=2,
        vocab_size=1000,
        max_position_embeddings=128
    )
    model = AliceForCausalLM(config)
    params = sum(p.numel() for p in model.parameters())
    print(f'  [OK] Model created: {params:,} params')
except Exception as e:
    print(f'  [FAIL] Model creation failed: {e}')
    sys.exit(1)

print('  Step 3: Forward + backward pass...')
try:
    x = torch.randint(0, 1000, (2, 32))
    logits, loss = model(x, x)
    loss.backward()
    print(f'  [OK] Loss: {loss.item():.4f}')
except Exception as e:
    print(f'  [FAIL] Training failed: {e}')
    sys.exit(1)

print('  Step 4: Gradient compression...')
try:
    grads = {}
    for name, p in model.named_parameters():
        if p.grad is not None:
            grads[name] = p.grad.detach().cpu()
    comp = TopKCompressor(ratio=0.01)
    compressed = comp.compress(grads)
    print(f'  [OK] Compressed {len(grads)} gradients (format: {compressed.get(\"fmt\",\"?\")})')
except Exception as e:
    print(f'  [FAIL] Compression failed: {e}')
    sys.exit(1)

print('  Step 5: PS connectivity...')
try:
    r = requests.get('https://ps.aliceprotocol.org/status', timeout=15)
    if r.status_code == 200:
        print(f'  [OK] PS reachable (status: {r.status_code})')
    else:
        print(f'  [WARN] PS returned {r.status_code}')
except Exception as e:
    print(f'  [WARN] PS unreachable: {e}')

print()
print('  ALL SIMULATION STEPS PASSED')
print('  RESULT:PASS')
"@ 2>&1

$simPassed = $false
foreach ($line in $simResult) {
    Write-Host $line
    if ($line -match "RESULT:PASS") { $simPassed = $true }
}

if ($simPassed) {
    Log-Pass "Mining simulation complete"
} else {
    Log-Fail "Mining simulation failed - check errors above"
}
Write-Host ""

# ===== SUMMARY =====
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTIC SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PASS: $pass" -ForegroundColor Green -NoNewline
Write-Host "  |  " -NoNewline
Write-Host "FAIL: $fail" -ForegroundColor Red -NoNewline
Write-Host "  |  " -NoNewline
Write-Host "WARN: $warn" -ForegroundColor Yellow
Write-Host ""

if ($fail -gt 0) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "PROBLEMS FOUND - Fix [FAIL] items before mining" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Quick fix checklist:" -ForegroundColor Yellow
    Write-Host "    1. Python 3.9+: https://www.python.org/downloads/" -ForegroundColor White
    Write-Host "    2. PyTorch (GPU): pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121" -ForegroundColor White
    Write-Host "    3. PyTorch (CPU): pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu" -ForegroundColor White
    Write-Host "    4. Dependencies:  pip install requests psutil numpy" -ForegroundColor White
} elseif ($warn -gt 0) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "READY (with warnings)" -ForegroundColor Yellow
    Write-Host "  Mining should work but check [WARN] items." -ForegroundColor Yellow
} else {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "ALL CLEAR - Ready to mine!" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Start mining:" -ForegroundColor Cyan
Write-Host "    python alice_node.py mine --ps-url https://ps.aliceprotocol.org --device cuda" -ForegroundColor White
Write-Host "    (or --device cpu if no GPU)" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan

# Save report
$reportFile = "alice_diagnostic_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-Host "  Report saved: $reportFile" -ForegroundColor Gray
Write-Host ""

Read-Host "Press Enter to exit"
