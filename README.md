# Alice Node

[中文 →](README_CN.md)

**One repo, three roles, one command.**

Alice Node is the unified client for [Alice Protocol](https://aliceprotocol.org) — a decentralized AI training network. Mining, scoring, aggregating — all through a single entry point.

```bash
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node && ./install.sh
python alice_node.py mine
```

## Three Roles

### ⛏️ Mining
Train the Alice neural network and earn ALICE token rewards based on gradient quality.

```bash
python alice_node.py mine --gpus all
```

**Requirements:** 24GB+ VRAM (NVIDIA) or 24GB+ unified memory (Apple Silicon)

### 🛡️ Scoring
Run a scoring server to independently validate gradients submitted by miners.

```bash
python alice_node.py score --model-path ./model.pt --device cpu
```

**Requirements:** 32GB+ RAM, stake 5,000 ALICE

### 🔗 Aggregating
Run an aggregator node — collect, aggregate miner gradients and forward to the parameter server.

```bash
python alice_node.py aggregate --ps-url https://ps.aliceprotocol.org
```

**Requirements:** 64GB+ RAM, 1TB SSD, high-speed network, stake 20,000 ALICE

## Quick Start

```bash
# 1. Clone
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node

# 2. Install (auto-detects GPU, creates virtual environment)
./install.sh

# 3. Create wallet
python alice_node.py wallet create

# 4. Start mining
python alice_node.py mine
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `alice-node mine` | Start mining |
| `alice-node score` | Run scoring server |
| `alice-node aggregate` | Run aggregator node |
| `alice-node stake --role scorer --amount 5000` | Stake as scorer |
| `alice-node stake --role aggregator --amount 10000` | Stake as aggregator |
| `alice-node unstake --role scorer` | Unstake |
| `alice-node status` | View network status |
| `alice-node wallet create` | Create wallet |
| `alice-node wallet import` | Import wallet |
| `alice-node wallet balance` | Check balance |

## Hardware Requirements

| Role | GPU VRAM | System RAM | Disk | Network | ALICE Stake |
|------|----------|------------|------|---------|-------------|
| **Miner** | 24 GB+ | 16 GB | 20 GB | 10 Mbps | — |
| **Scorer** | Optional | 32 GB+ | 20 GB | 50 Mbps | 5,000 |
| **Aggregator** | — | 64 GB+ | 1 TB | 500 Mbps | 20,000 |

## Rewards

- **Total Supply:** 21,000,000 ALICE (fixed, never inflated)
- **Year 1–2 Budget:** 5,250,000 ALICE/year, halving every 2 years
- **Per-Round Reward:** ~600 ALICE (each round ≈ 60 minutes)
- **Miners:** 90%
- **Scorers:** 3%
- **Aggregators:** 4%
- **Parameter Server:** 3%

## Upgrading from Alice-Miner

The old `Alice-Miner` repo has been renamed to `Alice-Node`:

1. GitHub automatically redirects `V-SK/Alice-Miner` → `V-SK/Alice-Node`
2. The root-level `alice_miner.py` still works (shows deprecation notice)
3. `start_mining.sh` requires no changes
4. `~/.alice/wallet.json` wallets are fully compatible

**Recommended:** Use `python alice_node.py mine` — the new unified CLI.

## Multi-GPU Mining

Have multiple GPUs? One command launches a miner on every card:

```bash
export ALICE_ADDRESS="your_wallet_address"
./start_multi_gpu.sh
```

Model downloads once, shared across all GPUs. Each GPU runs an independent miner process.

```bash
./start_multi_gpu.sh --gpus 0,1,2,3    # Specific GPUs
./start_multi_gpu.sh --gpus 0-7         # Range
./stop_multi_gpu.sh                     # Stop all
tail -f ~/.alice/logs/miner-gpu*.log    # Monitor
```

**Requirements:** NVIDIA GPUs with 24GB+ VRAM each.

## Desktop App (Optional)

A desktop GUI is available for miners who prefer a graphical interface.

### Build from source
```bash
npm install
npm run tauri build
```

Requires: Node.js 18+, Rust 1.75+

## Links

- **Website:** [aliceprotocol.org](https://aliceprotocol.org)
- **Whitepaper:** [dl.aliceprotocol.org/whitepaper](https://dl.aliceprotocol.org/whitepaper)
- **PS Status:** [ps.aliceprotocol.org/status](https://ps.aliceprotocol.org/status)
- **Twitter:** [@Alice_AI102](https://twitter.com/Alice_AI102)

## License

MIT

## Staking Requirements

To run an aggregator node, you must stake **20,000 ALICE** tokens.

### Steps
1. Get ALICE tokens from mining or exchange
2. Call `stake_as_aggregator(amount=20000)` extrinsic on Alice chain
3. Register with PS using your staked address
4. Start the aggregator service

### Hardware Requirements
- 64GB RAM
- 1TB SSD
- 500Mbps network
- Stable connection to PS and miners
