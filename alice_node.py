#!/usr/bin/env python3
"""
Alice Node — Unified client for Alice Protocol.

Run any role in the Alice network from a single entry point:

    alice-node mine       Train Alice and earn ALICE tokens
    alice-node score      Validate miner gradients
    alice-node aggregate  Collect and aggregate gradients
    alice-node stake      Stake ALICE as scorer or aggregator
    alice-node unstake    Unstake ALICE
    alice-node status     Check network and staking status
    alice-node wallet     Create, import, export, or check balance

Learn more: https://aliceprotocol.org
"""

import argparse
import os
import sys

DEFAULT_PS_URL = "https://ps.aliceprotocol.org"
DEFAULT_RPC_URL = "wss://rpc.aliceprotocol.org"

BANNER = r"""
   _    _ _            _   _           _
  / \  | (_) ___ ___  | \ | | ___   __| | ___
 / _ \ | | |/ __/ _ \ |  \| |/ _ \ / _` |/ _ \
/ ___ \| | | (_|  __/ | |\  | (_) | (_| |  __/
/_/   \_\_|_|\___\___| |_| \_|\___/ \__,_|\___|

  Mine · Validate · Aggregate — One command.
  https://aliceprotocol.org
"""


def cmd_mine(args):
    """Start mining — train Alice and earn ALICE tokens."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "miner"))
    from alice_miner import main as miner_main

    # Rebuild sys.argv for the miner
    sys.argv = ["alice_miner", "--ps-url", args.ps_url]
    if args.address:
        sys.argv += ["--address", args.address]
    if args.gpus:
        sys.argv += ["--gpus", args.gpus]
    if args.precision:
        sys.argv += ["--precision", args.precision]
    if args.device:
        sys.argv += ["--device", args.device]
    if args.batch_size:
        sys.argv += ["--batch-size", str(args.batch_size)]
    if args.model_path:
        sys.argv += ["--model-path", args.model_path]
    if args.model_dir:
        sys.argv += ["--model-dir", args.model_dir]
    if args.instance_id:
        sys.argv += ["--instance-id", args.instance_id]
    if args.download_only:
        sys.argv += ["--download-only"]
    miner_main()


def cmd_score(args):
    """Start scoring — validate miner gradients."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "scorer"))
    from scoring_server import main as scorer_main

    sys.argv = ["scoring_server", "--port", str(args.port), "--device", args.device]
    if args.model_path:
        sys.argv += ["--model-path", args.model_path]
    if args.validation_dir:
        sys.argv += ["--validation-dir", args.validation_dir]
    scorer_main()


def cmd_aggregate(args):
    """Start aggregator — collect and aggregate miner gradients."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "aggregator"))
    from aggregator_node import main as aggregator_main

    sys.argv = ["aggregator_node", "--ps-url", args.ps_url, "--port", str(args.port)]
    if args.node_id:
        sys.argv += ["--node-id", args.node_id]
    aggregator_main()


def cmd_stake(args):
    """Stake ALICE to become a scorer or aggregator."""
    from common.chain import stake

    stake(role=args.role, amount=args.amount, rpc_url=args.rpc_url)


def cmd_unstake(args):
    """Unstake ALICE from scorer or aggregator role."""
    from common.chain import unstake

    unstake(role=args.role, rpc_url=args.rpc_url)


def cmd_status(args):
    """Check network status and your staking info."""
    from common.chain import status

    status(rpc_url=args.rpc_url, address=args.address)


def cmd_wallet(args):
    """Manage your ALICE wallet."""
    from common.wallet import wallet_command

    wallet_command(args.action)


def main():
    parser = argparse.ArgumentParser(
        prog="alice-node",
        description="Alice Node — Mine, Validate, or Aggregate for Alice Protocol",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  alice-node mine                              Start mining with default settings
  alice-node mine --gpus 0,1                   Mine with specific GPUs
  alice-node mine --gpus mps                   Mine on Apple Silicon
  alice-node score --device cpu                Start scoring on CPU
  alice-node aggregate                         Start aggregator node
  alice-node stake --role scorer --amount 5000 Stake as scorer
  alice-node wallet create                     Create a new wallet
  alice-node status                            Check network status

Learn more: https://aliceprotocol.org
        """,
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # ── Mine ──────────────────────────────────────────────────────────
    p_mine = subparsers.add_parser("mine", help="Start mining — train Alice and earn ALICE")
    p_mine.add_argument("--ps-url", default=DEFAULT_PS_URL, help="Parameter server URL")
    p_mine.add_argument("--address", help="Your ALICE address for rewards")
    p_mine.add_argument("--gpus", help="GPU selection: all, 0,1,2, mps, or cpu")
    p_mine.add_argument("--precision", default="fp16", help="fp16 or fp32 (default: fp16)")
    p_mine.add_argument("--device", help="Force device: cuda, mps, cpu")
    p_mine.add_argument("--batch-size", type=int, help="Training batch size")
    p_mine.add_argument("--model-path", help="Path to model weights (skip download)")
    p_mine.add_argument("--model-dir", help="Model cache directory (default: ~/.alice/models)")
    p_mine.add_argument("--instance-id", help="Miner instance ID (for multi-GPU)")
    p_mine.add_argument("--download-only", action="store_true", help="Download model and exit")
    p_mine.set_defaults(func=cmd_mine)

    # ── Score ─────────────────────────────────────────────────────────
    p_score = subparsers.add_parser("score", help="Start scoring — validate miner gradients")
    p_score.add_argument("--port", type=int, default=8090, help="Scorer HTTP port (default: 8090)")
    p_score.add_argument("--device", default="cpu", help="Device: cpu, cuda, mps (default: cpu)")
    p_score.add_argument("--model-path", help="Path to model weights")
    p_score.add_argument("--validation-dir", help="Path to validation shards directory")
    p_score.set_defaults(func=cmd_score)

    # ── Aggregate ─────────────────────────────────────────────────────
    p_agg = subparsers.add_parser("aggregate", help="Run aggregator node")
    p_agg.add_argument("--ps-url", default=DEFAULT_PS_URL, help="Parameter server URL")
    p_agg.add_argument("--port", type=int, default=8084, help="Aggregator HTTP port (default: 8084)")
    p_agg.add_argument("--node-id", help="Unique node identifier")
    p_agg.set_defaults(func=cmd_aggregate)

    # ── Stake ─────────────────────────────────────────────────────────
    p_stake = subparsers.add_parser("stake", help="Stake ALICE as scorer or aggregator")
    p_stake.add_argument("--role", required=True, choices=["scorer", "aggregator"])
    p_stake.add_argument("--amount", required=True, type=float, help="Amount of ALICE to stake")
    p_stake.add_argument("--rpc-url", default=DEFAULT_RPC_URL, help="Chain RPC URL")
    p_stake.set_defaults(func=cmd_stake)

    # ── Unstake ───────────────────────────────────────────────────────
    p_unstake = subparsers.add_parser("unstake", help="Unstake ALICE")
    p_unstake.add_argument("--role", required=True, choices=["scorer", "aggregator"])
    p_unstake.add_argument("--rpc-url", default=DEFAULT_RPC_URL, help="Chain RPC URL")
    p_unstake.set_defaults(func=cmd_unstake)

    # ── Status ────────────────────────────────────────────────────────
    p_status = subparsers.add_parser("status", help="Check network and staking status")
    p_status.add_argument("--rpc-url", default=DEFAULT_RPC_URL, help="Chain RPC URL")
    p_status.add_argument("--address", help="Address to check")
    p_status.set_defaults(func=cmd_status)

    # ── Wallet ────────────────────────────────────────────────────────
    p_wallet = subparsers.add_parser("wallet", help="Manage ALICE wallet")
    p_wallet.add_argument(
        "action",
        choices=["create", "import", "export", "balance"],
        help="Wallet action",
    )
    p_wallet.set_defaults(func=cmd_wallet)

    args = parser.parse_args()
    if not args.command:
        print(BANNER)
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
