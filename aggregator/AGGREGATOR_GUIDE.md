# Aggregator Guide

Run an aggregator node to help distribute training workload across miners and earn ALICE rewards.

## Requirements

| Component | Minimum      |
|-----------|--------------|
| RAM       | 64 GB        |
| SSD       | 1 TB         |
| Bandwidth | 500 Mbps     |
| CPU       | 4+ cores     |
| GPU       | Not needed   |
| Stake     | 20,000 ALICE |

## Ports

| Port  | Direction | Purpose              |
|-------|-----------|----------------------|
| 8084  | Inbound   | Miners connect here  |
| 30333 | Inbound   | Chain P2P (full node)|

```bash
# Ubuntu/Debian
ufw allow 8084/tcp
ufw allow 30333/tcp
ufw reload
```

## Quick Start

```bash
git clone https://github.com/V-SK/Alice-Node
cd Alice-Node && ./install.sh

# Create wallet
python3 alice_node.py wallet create

# Fund with 20,000+ ALICE, then stake
python3 alice_node.py stake aggregator 20000

# Download shards (~224GB, ~30min on 1Gbps)
./scripts/download_shards.sh

# Start
python3 alice_node.py aggregate --ps-url https://ps.aliceprotocol.org
```

## Shard Download

First-time setup requires downloading 60,001 training shards (~224GB).
Uses aria2c with 8 parallel connections and resume support.

```bash
./scripts/download_shards.sh
```

You can also download a specific range:

```bash
# Download shards 0-999 only
./scripts/download_shards.sh ./data 0 999
```

### Estimated Download Time

| Bandwidth | Time     |
|-----------|----------|
| 1 Gbps   | ~30 min  |
| 500 Mbps | ~60 min  |
| 100 Mbps | ~5 hours |

## How It Works

1. You stake 20,000 ALICE on-chain as an aggregator
2. The PS discovers your node automatically each epoch
3. PS verifies: health check → RAM ≥ 64GB → model sync → activate
4. Miners get assigned to your aggregator node
5. You aggregate gradients locally, submit to PS
6. Earn ALICE rewards proportional to work done

## Monitoring

Check your aggregator status:

```bash
# Health check
curl http://localhost:8084/health

# View logs
tail -f aggregator.log
```
