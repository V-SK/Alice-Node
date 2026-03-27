#!/usr/bin/env bash
set -euo pipefail

# Alice Protocol — Scorer Node Startup Script
# Usage: ./start_scorer.sh --model-path /path/to/model.pt --validation-dir /path/to/shards/ [--port 8090] [--device cpu|cuda|mps]

PORT="${ALICE_SCORER_PORT:-8090}"
DEVICE="${ALICE_SCORER_DEVICE:-cpu}"
MODEL_PATH=""
VALIDATION_DIR=""
LOG_DIR="logs"
NUM_VAL_SHARDS=5

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model-path) MODEL_PATH="$2"; shift 2 ;;
        --validation-dir) VALIDATION_DIR="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --num-val-shards) NUM_VAL_SHARDS="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./start_scorer.sh --model-path PATH --validation-dir PATH [--port PORT] [--device DEVICE]"
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ -z "$MODEL_PATH" ]]; then
    echo "❌ --model-path required"
    echo "Usage: ./start_scorer.sh --model-path /path/to/model.pt --validation-dir /path/to/shards"
    exit 1
fi

if [[ -z "$VALIDATION_DIR" ]]; then
    echo "❌ --validation-dir required"
    echo "Usage: ./start_scorer.sh --model-path /path/to/model.pt --validation-dir /path/to/shards"
    exit 1
fi

cd "$ROOT_DIR"

# Activate venv if exists
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
fi

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/scoring-server.log"

echo "Starting Alice Scoring Server"
echo "  Model:    $MODEL_PATH"
echo "  Device:   $DEVICE"
echo "  Port:     $PORT"
echo "  Log:      $LOG_FILE"
echo ""

CMD=(python3 "$SCRIPT_DIR/scoring_server.py"
    --model-path "$MODEL_PATH"
    --validation-dir "$VALIDATION_DIR"
    --port "$PORT"
    --device "$DEVICE"
    --num-val-shards "$NUM_VAL_SHARDS"
)

exec "${CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
