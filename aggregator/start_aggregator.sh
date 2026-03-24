#!/usr/bin/env bash
set -euo pipefail

# Alice Protocol — Aggregator Node Startup Script
# Usage: ./start_aggregator.sh [--ps-url URL] [--port PORT] [--node-id ID]

PS_URL="${ALICE_PS_URL:-https://ps.aliceprotocol.org}"
PORT="${ALICE_AGG_PORT:-8084}"
NODE_ID="${ALICE_NODE_ID:-agg-$(hostname -s)}"
LOG_DIR="logs"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ps-url) PS_URL="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --node-id) NODE_ID="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./start_aggregator.sh [--ps-url URL] [--port PORT] [--node-id ID]"
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

cd "$ROOT_DIR"

# Activate venv if exists
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
fi

mkdir -p "$LOG_DIR" data/shards models

LOG_FILE="$LOG_DIR/aggregator.log"

echo "Starting Alice Aggregator Node"
echo "  PS URL:   $PS_URL"
echo "  Port:     $PORT"
echo "  Node ID:  $NODE_ID"
echo "  Log:      $LOG_FILE"
echo ""

exec python3 "$SCRIPT_DIR/aggregator_node.py" \
    --ps-url "$PS_URL" \
    --port "$PORT" \
    --node-id "$NODE_ID" \
    2>&1 | tee -a "$LOG_FILE"
