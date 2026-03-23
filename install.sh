#!/usr/bin/env bash
set -euo pipefail

# Alice Protocol Miner - One-Click Installer
# Usage: ./install.sh
# Skip venv: ALICE_NO_VENV=1 ./install.sh

VENV_DIR=".venv"
MIN_PYTHON="3.10"

echo "╔═══════════════════════════════════════╗"
echo "║   Alice Protocol Miner - Installer    ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# ── Step 1: Find Python 3.10+ ──────────────────────────────────

find_python() {
  for cmd in python3.12 python3.11 python3.10 python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
      local ver
      ver="$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || true)"
      if [[ -n "$ver" ]]; then
        local major minor
        major="${ver%%.*}"
        minor="${ver#*.}"
        if [[ "$major" -ge 3 && "$minor" -ge 10 ]]; then
          echo "$cmd"
          return 0
        fi
      fi
    fi
  done
  return 1
}

PYTHON_BIN=$(find_python) || {
  echo "Python 3.10+ not found."
  echo ""
  echo "Install it:"
  echo "  Ubuntu/Debian:  sudo apt install python3 python3-venv python3-pip"
  echo "  macOS:          brew install python@3.12"
  echo "  Windows:        https://python.org/downloads/"
  echo ""
  exit 1
}

PYTHON_VER="$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')")"
echo "[1/4] Python: $PYTHON_BIN ($PYTHON_VER)"

# ── Step 2: Create venv ─────────────────────────────────────────

if [[ "${ALICE_NO_VENV:-0}" == "1" ]]; then
  echo "[2/4] Skipping venv (ALICE_NO_VENV=1)"
  PIP="$PYTHON_BIN -m pip"
else
  if [[ ! -d "$VENV_DIR" ]]; then
    echo "[2/4] Creating virtual environment..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  else
    echo "[2/4] Virtual environment exists"
  fi

  # Activate
  if [[ -f "$VENV_DIR/bin/activate" ]]; then
    source "$VENV_DIR/bin/activate"
  elif [[ -f "$VENV_DIR/Scripts/activate" ]]; then
    source "$VENV_DIR/Scripts/activate"
  fi
  PIP="pip"
fi

# ── Step 3: Detect GPU & install PyTorch ────────────────────────

detect_gpu() {
  # NVIDIA CUDA
  if command -v nvidia-smi >/dev/null 2>&1; then
    local cuda_ver
    cuda_ver="$(nvidia-smi 2>/dev/null | grep -o 'CUDA Version: [0-9]*\.[0-9]*' | head -1 | sed 's/CUDA Version: //' || true)"
    if [[ -n "$cuda_ver" ]]; then
      echo "cuda:$cuda_ver"
      return
    fi
  fi

  # macOS MPS
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local chip
    chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    if echo "$chip" | grep -qi "apple"; then
      echo "mps"
      return
    fi
  fi

  echo "cpu"
}

GPU_INFO="$(detect_gpu)"
GPU_TYPE="${GPU_INFO%%:*}"

echo "[3/4] Installing PyTorch ($GPU_TYPE)..."

case "$GPU_TYPE" in
  cuda)
    CUDA_VER="${GPU_INFO#cuda:}"
    CUDA_MAJOR="${CUDA_VER%%.*}"
    if [[ "$CUDA_MAJOR" -ge 12 ]]; then
      $PIP install --upgrade torch --index-url https://download.pytorch.org/whl/cu124 -q
    elif [[ "$CUDA_MAJOR" -ge 11 ]]; then
      $PIP install --upgrade torch --index-url https://download.pytorch.org/whl/cu118 -q
    else
      echo "  CUDA $CUDA_VER too old, falling back to CPU PyTorch"
      $PIP install --upgrade torch -q
    fi
    ;;
  mps)
    # macOS: default pip torch includes MPS support
    $PIP install --upgrade torch -q
    ;;
  cpu)
    $PIP install --upgrade torch --index-url https://download.pytorch.org/whl/cpu -q
    ;;
esac

# Install other dependencies
if [[ -f "requirements.txt" ]]; then
  $PIP install -r requirements.txt -q
fi

# ── Step 4: Verify ──────────────────────────────────────────────

echo "[4/4] Verifying installation..."
echo ""

"$PYTHON_BIN" -c "
import torch
import sys

device = 'cpu'
mem = 'N/A'
if torch.cuda.is_available():
    device = f'CUDA ({torch.cuda.get_device_name(0)})'
    mem = f'{torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB'
elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
    device = 'MPS (Apple Silicon)'
    import subprocess
    result = subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True)
    if result.returncode == 0:
        mem = f'{int(result.stdout.strip()) / 1e9:.1f} GB (unified)'

print(f'  PyTorch:  {torch.__version__}')
print(f'  Device:   {device}')
print(f'  Memory:   {mem}')
print(f'  Python:   {sys.version.split()[0]}')
print()
"

echo "Installation complete!"
echo ""
echo "To start mining:"
echo "  ./start_mining.sh"
echo ""
