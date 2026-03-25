#!/usr/bin/env bash
set -euo pipefail

# Alice Node — Multi-GPU Launcher
# Automatically detects all GPUs and spawns one miner per GPU.
#
# Usage:
#   ./start_multi_gpu.sh              # All GPUs
#   ./start_multi_gpu.sh --gpus 0,1,2,3  # Specific GPUs
#   ./start_multi_gpu.sh --gpus 0-7      # Range

PS_URL="${ALICE_PS_URL:-https://ps.aliceprotocol.org}"
ADDRESS="${ALICE_ADDRESS:-}"
MODEL_DIR="${ALICE_MODEL_DIR:-$HOME/.alice/models}"
LOG_DIR="${ALICE_LOG_DIR:-$HOME/.alice/logs}"
GPUS="${1:-all}"

mkdir -p "$MODEL_DIR" "$LOG_DIR"

# Detect GPUs
if [[ "$GPUS" == "all" || "$GPUS" == "--gpus all" ]]; then
    NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l)
    if [[ "$NUM_GPUS" -eq 0 ]]; then
        echo "❌ No NVIDIA GPUs detected"
        exit 1
    fi
    GPU_LIST=$(seq 0 $((NUM_GPUS - 1)))
    echo "🔍 Detected $NUM_GPUS GPUs"
else
    # Parse --gpus 0,1,2 or 0-7
    GPUS="${GPUS#--gpus }"
    if [[ "$GPUS" == *-* ]]; then
        START="${GPUS%-*}"
        END="${GPUS#*-}"
        GPU_LIST=$(seq "$START" "$END")
    else
        GPU_LIST=$(echo "$GPUS" | tr ',' '\n')
    fi
    NUM_GPUS=$(echo "$GPU_LIST" | wc -w)
fi

echo "╔══════════════════════════════════════════╗"
echo "║       Alice Node — Multi-GPU Mining      ║"
echo "║  GPUs: $NUM_GPUS                              ║"
echo "║  PS:   $PS_URL"
echo "╚══════════════════════════════════════════╝"
echo ""

# Download model once before spawning workers
echo "📥 Pre-downloading model (shared by all GPUs)..."
CUDA_VISIBLE_DEVICES=0 python3 alice_node.py mine \
    --ps-url "$PS_URL" \
    --model-dir "$MODEL_DIR" \
    --download-only 2>/dev/null || true

# Spawn one miner per GPU
PIDS=()
for GPU_ID in $GPU_LIST; do
    INSTANCE_ID="gpu-${GPU_ID}"
    LOG_FILE="$LOG_DIR/miner-gpu${GPU_ID}.log"

    echo "🚀 Starting miner on GPU $GPU_ID (instance: $INSTANCE_ID)..."

    CUDA_VISIBLE_DEVICES=$GPU_ID python3 alice_node.py mine \
        --ps-url "$PS_URL" \
        --instance-id "$INSTANCE_ID" \
        --model-dir "$MODEL_DIR" \
        --device cuda \
        ${ADDRESS:+--address "$ADDRESS"} \
        > "$LOG_FILE" 2>&1 &
    PIDS+=($!)
    sleep 2  # Stagger startup to avoid download race
done

echo ""
echo "✅ $NUM_GPUS miners launched"
echo "   Logs: $LOG_DIR/miner-gpu*.log"
echo "   PIDs: ${PIDS[*]}"
echo ""
echo "Monitor: tail -f $LOG_DIR/miner-gpu*.log"
echo "Stop all: kill ${PIDS[*]}"

# Save PIDs for stop script
echo "${PIDS[*]}" > "$LOG_DIR/.miner_pids"

# Wait for all
wait
