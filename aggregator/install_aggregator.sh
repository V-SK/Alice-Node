#!/usr/bin/env bash
set -euo pipefail

# Alice Protocol — Aggregator Node Installer
# Usage: ./install_aggregator.sh

echo "╔═══════════════════════════════════════════╗"
echo "║  Alice Protocol — Aggregator Installer    ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

VENV_DIR="../.venv"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

# Check Python
PYTHON_BIN=""
for cmd in python3.12 python3.11 python3.10 python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ver="$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || true)"
        major="${ver%%.*}"
        minor="${ver#*.}"
        if [[ "$major" -ge 3 && "$minor" -ge 10 ]]; then
            PYTHON_BIN="$cmd"
            break
        fi
    fi
done

if [[ -z "$PYTHON_BIN" ]]; then
    echo "❌ Python 3.10+ required. Install it first."
    exit 1
fi
echo "[1/3] Python: $PYTHON_BIN ($("$PYTHON_BIN" --version 2>&1))"

# Create venv if needed
if [[ ! -d "$VENV_DIR" ]]; then
    echo "[2/3] Creating virtual environment..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
else
    echo "[2/3] Virtual environment exists"
fi

source "$VENV_DIR/bin/activate" 2>/dev/null || source "$VENV_DIR/Scripts/activate" 2>/dev/null

# Install deps
echo "[3/3] Installing dependencies..."
pip install -q flask requests torch numpy substrate-interface

echo ""
echo "✅ Aggregator dependencies installed!"
echo ""
echo "To start the aggregator:"
echo "  ./aggregator/start_aggregator.sh"
echo ""
echo "Or using alice-node:"
echo "  python alice_node.py aggregate --ps-url https://ps.aliceprotocol.org"
echo ""
