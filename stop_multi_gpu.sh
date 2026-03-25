#!/usr/bin/env bash
# Alice Node — Stop Multi-GPU Miners

LOG_DIR="${ALICE_LOG_DIR:-$HOME/.alice/logs}"

if [[ -f "$LOG_DIR/.miner_pids" ]]; then
    PIDS=$(cat "$LOG_DIR/.miner_pids")
    echo "Stopping miners: $PIDS"
    kill $PIDS 2>/dev/null
    rm "$LOG_DIR/.miner_pids"
    echo "✅ All miners stopped"
else
    echo "No running miners found"
    pkill -f "alice_node.py mine" 2>/dev/null && echo "✅ Killed all miners" || echo "Nothing to kill"
fi
