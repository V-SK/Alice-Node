# Alice Scorer — Deployment Guide

Earn **3% of all ALICE rewards** by validating gradient quality for the Alice training network.

---

## What Does a Scorer Do?

Scorers verify that miners are submitting real training work, not garbage. Each submitted gradient is scored by running a forward pass on the model — if the gradient improves model quality, it gets a positive score. Miners with higher scores earn more rewards.

**You are the quality control layer of the network.**

---

## Requirements

| Component | Minimum     | Recommended |
|-----------|-------------|-------------|
| RAM       | 24 GB       | 32 GB       |
| CPU       | 4 cores     | 8+ cores    |
| GPU       | Not needed  | Not needed  |
| Disk      | 50 GB       | 100 GB      |
| Network   | 10 Mbps     | 50 Mbps+    |
| Python    | 3.10+       | 3.11+       |
| Stake     | 5,000 ALICE | 5,000 ALICE |

**No GPU required.** Scoring runs on CPU and takes ~5-15 seconds per gradient. CPU mode is actually faster than GPU for this workload.

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node

# 2. Install (creates wallet automatically)
chmod +x install_scorer.sh
./install_scorer.sh

# 3. Fund your scorer wallet
#    Send 5,000+ ALICE to the address shown during install

# 4. Stake on chain
#    See "Staking" section below

# 5. Start scoring
./start_scorer.sh
```

**Five steps to earning.** The scorer will automatically sync the latest model and begin scoring.

---

## Staking

Before your scorer can receive scoring tasks, you must stake **5,000 ALICE** on chain.

### Using polkadot.js

1. Go to https://polkadot.js.org/apps/?rpc=wss://rpc.aliceprotocol.org
2. Navigate to **Developer → Extrinsics**
3. Select your scorer account
4. Choose: `aliceTraining` → `stakeAsScorer`
5. Parameters:
   - `amount`: `5000000000000000` (5,000 ALICE in base units)
   - `endpoint`: `http://YOUR_IP:8090` (your scorer's public endpoint)
6. Submit Transaction

### Using CLI

```python
python3 -c "
from substrateinterface import SubstrateInterface, Keypair
import json

# Load wallet
wallet = json.load(open('~/.alice/scorer_wallet.json'))
keypair = Keypair.create_from_mnemonic(wallet['mnemonic'])

# Connect to chain
substrate = SubstrateInterface(url='wss://rpc.aliceprotocol.org')

# Stake
call = substrate.compose_call(
    call_module='AliceTraining',
    call_function='stake_as_scorer',
    call_params={
        'amount': 5_000_000_000_000_000,   # 5000 ALICE
        'endpoint': 'http://YOUR_IP:8090',
    }
)
extrinsic = substrate.create_signed_extrinsic(call=call, keypair=keypair)
receipt = substrate.submit_extrinsic(extrinsic, wait_for_inclusion=True)
print(f'Staked! TX: {receipt.extrinsic_hash}')
"
```

> **Important:** Replace `YOUR_IP` with your server's public IP address. Port 8090 must be accessible from the internet.

---

## What Happens After Staking

1. **Pending** — Your stake is locked, scorer is registered on chain
2. **Verification** — Next epoch, the Parameter Server automatically:
   - Checks your `/health` endpoint
   - Verifies RAM ≥ 24GB
   - Syncs latest model to your scorer
   - Runs a test scoring (honeypot)
3. **Active** — All checks pass → your scorer is activated on chain
4. **Earning** — You start receiving scoring tasks and earning rewards

**No manual approval needed. Fully automated.**

---

## Rewards

| Parameter       | Value                                         |
|-----------------|-----------------------------------------------|
| Pool            | 3% of all ALICE rewards                       |
| Distribution    | Proportional to gradients scored per epoch     |
| Extra scoring   | Fast scorers can request additional tasks      |
| Epoch duration  | ~1 hour                                       |

**Example:** 5 scorers. You score 120 gradients, others average 100 each.
→ You earn `120 / 520 = 23%` of the 3% pool that epoch.

**Extra scoring:** After completing your base allocation, your scorer can request additional unscored gradients via `/scoring/request_extra`. Score more, earn more — up to 3x your base workload.

---

## Monitoring

```bash
# Check health
curl http://localhost:8090/health

# View logs
tail -f scorer.log

# Check chain status
curl -s https://ps.aliceprotocol.org/status | python3 -m json.tool
```

### Health endpoint response

```json
{
  "status": "ok",
  "model_version": 6,
  "scored_count": 142,
  "system_memory_gb": 32,
  "available_memory_gb": 18,
  "cpu_count": 8,
  "uptime": 3600
}
```

---

## Unstaking

**7-day cooldown period** to prevent stake-and-slash attacks.

```python
# 1. Start cooldown
python3 -c "
from substrateinterface import SubstrateInterface, Keypair
import json

wallet = json.load(open('~/.alice/scorer_wallet.json'))
keypair = Keypair.create_from_mnemonic(wallet['mnemonic'])
substrate = SubstrateInterface(url='wss://rpc.aliceprotocol.org')

call = substrate.compose_call('AliceTraining', 'unstake_scorer', {})
extrinsic = substrate.create_signed_extrinsic(call=call, keypair=keypair)
receipt = substrate.submit_extrinsic(extrinsic, wait_for_inclusion=True)
print(f'Cooldown started. Wait 7 days then withdraw.')
"
```

```python
# 2. After 7 days, withdraw
python3 -c "
from substrateinterface import SubstrateInterface, Keypair
import json

wallet = json.load(open('~/.alice/scorer_wallet.json'))
keypair = Keypair.create_from_mnemonic(wallet['mnemonic'])
substrate = SubstrateInterface(url='wss://rpc.aliceprotocol.org')

call = substrate.compose_call('AliceTraining', 'withdraw_stake', {})
extrinsic = substrate.create_signed_extrinsic(call=call, keypair=keypair)
receipt = substrate.submit_extrinsic(extrinsic, wait_for_inclusion=True)
print(f'Stake withdrawn!')
"
```

---

## Slashing

Dishonest scorers lose their stake:

| Strikes | Penalty                             |
|---------|-------------------------------------|
| 5       | 24h suspension                      |
| 10      | 10% stake slashed (500 ALICE burned)|
| 15      | 50% slashed (2,500 ALICE burned)    |
| 20      | 100% slashed + permanent removal    |

Strikes are earned by:
- Failing honeypot tests (known-answer scoring checks)
- Large discrepancies with other scorers (cross-validation)
- Repeated health check failures
- Statistical bias toward specific miners

**Slashed ALICE is burned** (not given to anyone), preventing collusion incentives.

---

## Architecture

```
Miner trains on GPU
  → submits gradient to PS
    → PS samples 10% for real scoring
      → sends gradient to your scorer
        → your scorer: load gradient → forward pass → score
          → returns score to PS
            → PS uses score for reward distribution

Fast scorers can request extra tasks:
  → POST /scoring/request_extra
    → score additional gradients beyond base 10%
      → earn proportionally more rewards
```

---

## Troubleshooting

| Issue                | Fix                                            |
|----------------------|------------------------------------------------|
| Not receiving tasks  | Check stake is `Active` on chain               |
| Model download slow  | Scorer auto-syncs; wait for first epoch         |
| High memory usage    | Ensure `--device cpu` (not mps/cuda)           |
| 403 errors           | Check wallet matches staked address             |
| Health check failing | Ensure port 8090 is accessible from internet    |
| Connection refused   | Check scorer is running: `pgrep -f scoring`    |

---

## FAQ

### Do I need a GPU?

**No.** CPU is actually faster for scoring (~12s vs ~21s on MPS). No GPU needed, no CUDA, no drivers.

### How much can I earn?

Depends on number of active scorers:

| Scorers | ALICE/year each (approx) |
|---------|--------------------------|
| 3       | ~52,500                  |
| 5       | ~31,500                  |
| 10      | ~15,750                  |
| 20      | ~7,875                   |

### Can I run a scorer and mine at the same time?

Yes, on **different machines**. Scorer needs 24GB RAM (CPU), miner needs 24GB VRAM (GPU). They don't compete for resources.

### Can I run a scorer on the same machine as a miner?

Technically yes if you have 48GB+ RAM, but **not recommended**. Keep them separate for reliability.

### What happens if my scorer goes offline?

3 missed health checks → temporary suspension. Come back online → automatically re-verified next epoch. **No slashing for downtime**, only for dishonesty.

### How do I update the scorer?

```bash
# Pull latest
git pull
# Restart
pkill -f scoring_server
./start_scorer.sh
```

Model updates happen automatically — the PS sends a `/reload` request when a new model version is available.

---

## Firewall

Your scorer needs port **8090** open for incoming connections from the Parameter Server.

```bash
# Ubuntu/Debian
ufw allow 8090/tcp
ufw reload

# Or if behind NAT, set up port forwarding on your router
```

The PS will connect to your scorer at the endpoint you registered during staking. Make sure this endpoint is reachable from the internet.

| Port | Direction | Purpose             |
|------|-----------|---------------------|
| 8090 | Inbound   | PS sends score tasks |

---

## Links

- [Alice Protocol](https://aliceprotocol.org)
- [PS Status](https://ps.aliceprotocol.org/status)
- [Chain Explorer](https://polkadot.js.org/apps/?rpc=wss://rpc.aliceprotocol.org)
- [GitHub](https://github.com/V-SK/alice-project)
- [Discord](https://discord.gg/alice)
