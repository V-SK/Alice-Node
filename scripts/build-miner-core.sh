#!/bin/bash
# Build alice-miner-core binary using PyInstaller

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINER_DIR="$SCRIPT_DIR/../miner-core"
OUTPUT_DIR="$SCRIPT_DIR/../src-tauri/binaries"

echo "Building alice-miner-core..."

# Create output directory
mkdir -p "$OUTPUT_DIR"

ENTRY_SCRIPT="alice_node.py"
if [ ! -f "$MINER_DIR/$ENTRY_SCRIPT" ]; then
    echo "Error: no miner entry script found in $MINER_DIR"
    echo "Expected alice_node.py"
    exit 1
fi

cd "$MINER_DIR"

# Install dependencies if needed
pip install pyinstaller torch --quiet

# Build with PyInstaller
pyinstaller \
    --onefile \
    --name alice-miner-core \
    --hidden-import torch \
    --hidden-import numpy \
    --hidden-import requests \
    --hidden-import websocket \
    --strip \
    --noconfirm \
    "$ENTRY_SCRIPT"

# Copy to binaries directory
cp dist/alice-miner-core "$OUTPUT_DIR/"

echo "Build complete: $OUTPUT_DIR/alice-miner-core"
