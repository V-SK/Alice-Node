#!/usr/bin/env bash
set -euo pipefail

ADDRESS=""
GPUS="all"
PS_URL="https://ps.aliceprotocol.org"
PRECISION="fp16"
LOG_DIR="logs"
PYTHON_BIN="python3"
MINER_SCRIPT="alice_miner.py"
DRY_RUN=0
EXTRA_ARGS=()

usage() {
  cat <<EOF
Usage:
  ./start_mining.sh --address a1... [--gpus 0,1,2,3|all|cpu|mps] [--ps-url URL] [--precision fp16|fp32|auto] [--dry-run]

Examples:
  ./start_mining.sh --address a1xxxx --gpus 0,1,2,3
  ./start_mining.sh --address a1xxxx --gpus all
  ./start_mining.sh --address a1xxxx --gpus cpu
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --address) ADDRESS="$2"; shift 2 ;;
    --gpus) GPUS="$2"; shift 2 ;;
    --ps-url) PS_URL="$2"; shift 2 ;;
    --precision) PRECISION="$2"; shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    --python) PYTHON_BIN="$2"; shift 2 ;;
    --miner-script) MINER_SCRIPT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$ADDRESS" ]]; then
  echo "Error: --address is required"
  usage
  exit 1
fi

if [[ ! -f "$MINER_SCRIPT" ]]; then
  echo "Error: miner script not found: $MINER_SCRIPT"
  exit 1
fi

mkdir -p "$LOG_DIR"

ALLOW_INSECURE_ARGS=()
if [[ "$PS_URL" == http://* ]]; then
  ALLOW_INSECURE_ARGS+=("--allow-insecure")
fi

# Stop old miners for this address only
mapfile -t OLD_PIDS < <(pgrep -af "alice_miner.py" | awk -v a="$ADDRESS" '$0 ~ ("--address " a) {print $1}')
if [[ ${#OLD_PIDS[@]} -gt 0 ]]; then
  echo "Stopping ${#OLD_PIDS[@]} existing miner process(es) for address $ADDRESS..."
  kill "${OLD_PIDS[@]}" 2>/dev/null || true
  sleep 1
fi

resolve_gpu_list() {
  local g="$1"
  if [[ "$g" == "all" ]]; then
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=index --format=csv,noheader | tr -d ' ' | paste -sd, -
    else
      echo "cpu"
    fi
  else
    echo "$g"
  fi
}

GPU_LIST="$(resolve_gpu_list "$GPUS")"
if [[ -z "$GPU_LIST" ]]; then
  GPU_LIST="cpu"
fi

IFS=',' read -r -a TARGETS <<< "$GPU_LIST"

echo "Starting miners"
echo "  address:   $ADDRESS"
echo "  ps-url:    $PS_URL"
echo "  targets:   ${TARGETS[*]}"
echo "  precision: $PRECISION"

count=0
for t in "${TARGETS[@]}"; do
  t="${t// /}"
  [[ -z "$t" ]] && continue

  INSTANCE_ID=""
  LOG_PATH=""
  CMD=("$PYTHON_BIN" "$MINER_SCRIPT" "--ps-url" "$PS_URL" "--address" "$ADDRESS" "--precision" "$PRECISION")
  CMD+=("${ALLOW_INSECURE_ARGS[@]}")

  if [[ "$t" == "cpu" || "$t" == "mps" ]]; then
    INSTANCE_ID="$t"
    LOG_PATH="$LOG_DIR/$t.log"
    CMD+=("--instance-id" "$INSTANCE_ID" "--device" "$t")
    if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
      CMD+=("${EXTRA_ARGS[@]}")
    fi
    echo "[$((count+1))] $t -> $LOG_PATH"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY_RUN: %q ' "${CMD[@]}"; echo
    else
      nohup "${CMD[@]}" > "$LOG_PATH" 2>&1 &
      echo "    pid=$!"
    fi
    count=$((count+1))
    continue
  fi

  INSTANCE_ID="gpu$t"
  LOG_PATH="$LOG_DIR/gpu$t.log"
  CMD+=("--instance-id" "$INSTANCE_ID" "--device" "cuda")
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    CMD+=("${EXTRA_ARGS[@]}")
  fi

  echo "[$((count+1))] GPU $t -> $LOG_PATH"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY_RUN: CUDA_VISIBLE_DEVICES=%s ' "$t"; printf '%q ' "${CMD[@]}"; echo
  else
    CUDA_VISIBLE_DEVICES="$t" nohup "${CMD[@]}" > "$LOG_PATH" 2>&1 &
    echo "    pid=$!"
  fi
  count=$((count+1))
  sleep 1

done

echo "Done. started=$count"
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "Logs: tail -f $LOG_DIR/*.log"
fi
