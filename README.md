# Alice Node

[中文版 →](README_CN.md)

**One repo. Three roles. One command.**

Alice Node is the unified client for [Alice Protocol](https://aliceprotocol.org) — the decentralized AI training network. Mine, validate, or aggregate — all from a single entry point.

```bash
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node && ./install.sh
python alice_node.py mine
```

## Three Roles

### ⛏️ Mine
Train Alice's neural network and earn ALICE tokens proportional to your gradient quality.

```bash
python alice_node.py mine --gpus all
```

**Requirements:** 24GB+ VRAM (NVIDIA) or 24GB+ unified memory (Apple Silicon)

### 🛡️ Validate (Score)
Run a scoring server that independently validates miner gradient submissions.

```bash
python alice_node.py score --model-path ./model.pt --device cpu
```

**Requirements:** 32GB+ RAM, stake 5,000 ALICE

### 🔗 Aggregate
Operate an aggregator node — collect, aggregate, and relay miner gradients to the parameter server.

```bash
python alice_node.py aggregate --ps-url https://ps.aliceprotocol.org
```

**Requirements:** 16GB+ RAM, fast network, stake 10,000 ALICE

## Quick Start

```bash
# 1. Clone
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node

# 2. Install (auto-detects GPU, creates venv)
./install.sh

# 3. Create a wallet
python alice_node.py wallet create

# 4. Start mining
python alice_node.py mine
```

## Command Reference

| Command | Description |
|---------|-------------|
| `alice-node mine` | Start mining (train Alice, earn ALICE) |
| `alice-node score` | Run scoring server (validate gradients) |
| `alice-node aggregate` | Run aggregator node |
| `alice-node stake --role scorer --amount 5000` | Stake as scorer |
| `alice-node stake --role aggregator --amount 10000` | Stake as aggregator |
| `alice-node unstake --role scorer` | Unstake from scorer role |
| `alice-node status` | Check network status & staking info |
| `alice-node wallet create` | Create new wallet |
| `alice-node wallet import` | Import wallet from mnemonic |
| `alice-node wallet export` | Export mnemonic (requires password) |
| `alice-node wallet balance` | Check ALICE balance |

## Hardware Requirements

| Role | GPU VRAM | System RAM | Disk | Network | ALICE Stake |
|------|----------|------------|------|---------|-------------|
| **Miner** | 24 GB+ | 16 GB | 20 GB | 10 Mbps | — |
| **Scorer** | Optional | 32 GB+ | 20 GB | 50 Mbps | 5,000 |
| **Aggregator** | — | 16 GB+ | 50 GB | 100 Mbps | 10,000 |

**Supported GPUs:** NVIDIA 24GB+ (RTX 3090, 4090, A5000, A6000, etc.) or Apple Silicon 24GB+.

## Mining

### start_mining.sh (recommended)

```bash
# All GPUs
./start_mining.sh --gpus all

# Specific GPUs
./start_mining.sh --gpus 0,1

# Apple Silicon
./start_mining.sh --gpus mps

# CPU only (not recommended)
./start_mining.sh --gpus cpu
```

### Direct Python

```bash
python alice_node.py mine \
  --ps-url https://ps.aliceprotocol.org \
  --gpus all \
  --precision fp16
```

### Mining Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--ps-url` | `https://ps.aliceprotocol.org` | Parameter server URL |
| `--address` | auto (from wallet) | Your ALICE address for rewards |
| `--gpus` | `all` | GPU selection: `all`, `0,1,2`, `mps`, `cpu` |
| `--precision` | `fp16` | `fp16` or `fp32` |
| `--device` | auto | Force device: `cuda`, `mps`, `cpu` |
| `--batch-size` | auto | Training batch size |
| `--model-path` | auto | Skip model download |

### Layer Assignment

| VRAM | Layers | Notes |
|------|--------|-------|
| 24 GB (CUDA) | 24 | Most consumer GPUs |
| 40 GB+ (CUDA) | 32 | Full model (A6000, etc.) |
| 32 GB (MPS) | 30 | Apple Silicon Max chips |
| 16 GB (MPS) | 14 | Apple Silicon (experimental) |

## Rewards

- **Total supply:** 21,000,000 ALICE (fixed, never more)
- **Year 1-2 budget:** 5,250,000 ALICE/year, halving every 2 years
- **Per-epoch reward:** ~600 ALICE (epoch ≈ 60 minutes)
- **Trainer share:** 56-90% (dynamic)
- **Infrastructure:** 9% fixed (validators 5% + aggregators 2% + scheduler 2%)

## Staking

Scorers and aggregators must stake ALICE to participate:

```bash
# Stake as scorer (min 5,000 ALICE)
python alice_node.py stake --role scorer --amount 5000

# Stake as aggregator (min 10,000 ALICE)
python alice_node.py stake --role aggregator --amount 10000

# Check status
python alice_node.py status

# Unstake (cooldown period applies)
python alice_node.py unstake --role scorer
```

## Wallet

```bash
# Create new wallet (generates 24-word mnemonic)
python alice_node.py wallet create

# Import from mnemonic
python alice_node.py wallet import

# Export mnemonic (requires password)
python alice_node.py wallet export

# Check balance
python alice_node.py wallet balance
```

Wallets are stored at `~/.alice/wallet.json`, encrypted with AES-256-GCM + PBKDF2.

## Project Structure

```
Alice-Node/
├── alice_node.py          # Unified CLI entry point
├── alice_miner.py         # Backward-compat wrapper (deprecated)
├── miner/
│   ├── alice_miner.py     # Mining client
│   ├── core/              # Model, compression, wallet
│   └── src/               # Compatibility shims
├── scorer/
│   ├── scoring_server.py  # Gradient validation server
│   ├── install_scorer.sh
│   └── start_scorer.sh
├── aggregator/
│   ├── aggregator_node.py # Gradient aggregation server
│   ├── streaming_aggregator.py
│   ├── install_aggregator.sh
│   └── start_aggregator.sh
├── common/
│   ├── wallet.py          # Wallet management
│   ├── chain.py           # Chain interaction (stake/unstake)
│   └── utils.py           # Shared utilities
├── install.sh             # Universal installer
├── start_mining.sh        # Mining startup script
├── requirements.txt
├── LICENSE
└── README.md
```

## Upgrading from Alice-Miner

If you were using the old `Alice-Miner` repository:

1. GitHub automatically redirects `V-SK/Alice-Miner` → `V-SK/Alice-Node`
2. `alice_miner.py` at root still works (prints deprecation notice)
3. `start_mining.sh` works unchanged
4. Wallets at `~/.alice/wallet.json` are fully compatible

**Recommended:** Switch to `python alice_node.py mine` for the new unified CLI.

## Vast.ai Setup

```bash
# Use /dev/shm for model storage (overlay disk is limited)
python alice_node.py mine \
  --model-path /dev/shm/models \
  --device cuda \
  --batch-size 2
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| OOM (Out of Memory) | `--batch-size 1` or `--precision fp16` |
| Vast.ai disk full | Use `--model-path /dev/shm/models` |
| Slow model download | Pre-download: `wget https://dl.aliceprotocol.org/models/latest.pt` |
| Connection refused | Check PS: `curl https://ps.aliceprotocol.org/status` |
| MPS crash | Use `--precision fp16 --batch-size 1` |

## Links

- **Website:** [aliceprotocol.org](https://aliceprotocol.org)
- **Whitepaper:** [dl.aliceprotocol.org/whitepaper](https://dl.aliceprotocol.org/whitepaper)
- **PS Status:** [ps.aliceprotocol.org/status](https://ps.aliceprotocol.org/status)
- **Twitter:** [@Alice_AI102](https://twitter.com/Alice_AI102)

## License

MIT
