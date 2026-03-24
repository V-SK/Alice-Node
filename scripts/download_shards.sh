#!/usr/bin/env bash
# download_shards.sh — Download SlimPajama-60B training shards via aria2c
#
# Usage:
#   ./download_shards.sh [DEST_DIR] [START_SHARD] [END_SHARD]
#
# Examples:
#   ./download_shards.sh ./data/slimpajama-60B        # Download all 60001 shards
#   ./download_shards.sh ./data/slimpajama-60B 0 999   # Download shards 0-999 only
#
# Requirements: aria2c, curl, jq (optional)

set -euo pipefail

BASE_URL="${SHARD_URL:-https://dl.aliceprotocol.org/shards}"
DEST_DIR="${1:-./data/slimpajama-60B}"
START="${2:-0}"
END="${3:-}"
PARALLEL="${ARIA2_CONNECTIONS:-8}"      # parallel downloads
SPLIT="${ARIA2_SPLIT:-1}"                # splits per file (1 = no splitting, shards are small)

# ---------- preflight ----------
if ! command -v aria2c &>/dev/null; then
  echo "ERROR: aria2c not found. Install with:"
  echo "  apt install aria2      # Debian/Ubuntu"
  echo "  brew install aria2     # macOS"
  exit 1
fi

mkdir -p "$DEST_DIR"

# ---------- fetch shard count ----------
echo "[*] Fetching shard index from ${BASE_URL}/shard_index.json ..."
INDEX_JSON=$(curl -sf "${BASE_URL}/shard_index.json" 2>/dev/null || echo "")
if [ -z "$INDEX_JSON" ]; then
  echo "WARN: Could not fetch shard_index.json, using END=${END:-60000}"
  TOTAL="${END:-60000}"
else
  TOTAL=$(echo "$INDEX_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_shards'])" 2>/dev/null || echo "60001")
  TOTAL=$((TOTAL - 1))  # 0-indexed
  echo "[*] Total shards: $((TOTAL + 1))"
fi

if [ -z "$END" ]; then
  END="$TOTAL"
fi

echo "[*] Downloading shards ${START}..${END} → ${DEST_DIR}"
echo "[*] Parallel connections: ${PARALLEL}"

# ---------- generate URL list ----------
URL_LIST=$(mktemp /tmp/shard_urls.XXXXXX)
trap "rm -f $URL_LIST" EXIT

count=0
for i in $(seq "$START" "$END"); do
  # Match the naming convention: shard_000000.pt .. shard_999.pt
  fname=$(printf "shard_%06d.pt" "$i")
  # Skip if already downloaded and non-zero
  if [ -f "${DEST_DIR}/${fname}" ] && [ -s "${DEST_DIR}/${fname}" ]; then
    continue
  fi
  echo "${BASE_URL}/${fname}"
  echo "  out=${fname}"
  count=$((count + 1))
done > "$URL_LIST"

if [ "$count" -eq 0 ]; then
  echo "[✓] All shards already present in ${DEST_DIR}. Nothing to download."
  exit 0
fi

echo "[*] ${count} shards to download (skipped already-present files)"

# ---------- download ----------
aria2c \
  --input-file="$URL_LIST" \
  --dir="$DEST_DIR" \
  --max-concurrent-downloads="$PARALLEL" \
  --split="$SPLIT" \
  --min-split-size=1M \
  --max-connection-per-server=1 \
  --continue=true \
  --auto-file-renaming=false \
  --console-log-level=notice \
  --summary-interval=30 \
  --retry-wait=5 \
  --max-tries=10 \
  --connect-timeout=30 \
  --timeout=120

# ---------- verify ----------
echo ""
echo "[*] Verifying download..."
actual=$(ls "${DEST_DIR}"/shard_*.pt 2>/dev/null | wc -l)
expected=$((END - START + 1))
echo "[*] Expected: ${expected}, Found: ${actual}"

if [ "$actual" -ge "$expected" ]; then
  echo "[✓] All shards downloaded successfully!"
  # Save index
  curl -sf "${BASE_URL}/shard_index.json" -o "${DEST_DIR}/shard_index.json" 2>/dev/null || true
else
  echo "[!] WARNING: Some shards may be missing. Re-run this script to resume."
  exit 1
fi
