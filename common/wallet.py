#!/usr/bin/env python3
"""
Alice Node — Wallet Management

Supports:
    create   Generate a new 24-word BIP39 mnemonic wallet
    import   Import wallet from mnemonic phrase
    export   Display mnemonic (requires password confirmation)
    balance  Query on-chain ALICE balance

Wallet file: ~/.alice/wallet.json
SS58 format: 300 (prefix 'a2')
"""

import json
import os
import sys
from pathlib import Path

# Re-use the secure wallet module from the miner core
_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT / "miner"))

from core.secure_wallet import (
    DEFAULT_WALLET_PATH,
    create_wallet_interactive,
    unlock_wallet_interactive,
    import_wallet_interactive,
    export_mnemonic_interactive,
    load_wallet_public,
)


def _balance(wallet_path: Path = DEFAULT_WALLET_PATH):
    """Query on-chain balance for the local wallet address."""
    info = load_wallet_public(wallet_path)
    address = info["address"]
    print(f"🔑 Address: {address}")

    # Try querying via the RPC endpoint
    rpc_url = os.environ.get("ALICE_RPC_URL", "wss://rpc.aliceprotocol.org")

    try:
        from substrateinterface import SubstrateInterface

        substrate = SubstrateInterface(url=rpc_url)
        result = substrate.query("System", "Account", [address])
        free = result.value["data"]["free"]
        # Convert from smallest unit (1 ALICE = 10^18 planck)
        balance_alice = free / 10**18
        print(f"💰 Balance: {balance_alice:,.4f} ALICE")
        print(f"🔗 RPC: {rpc_url}")
    except ImportError:
        print("⚠️  substrate-interface not installed. Install with:")
        print("    pip install substrate-interface")
        print(f"\n📋 Check balance manually at the explorer with address: {address}")
    except Exception as e:
        print(f"⚠️  Could not query chain: {e}")
        print(f"📋 Address: {address}")
        print("   Check balance at: https://aliceprotocol.org/explorer")


def wallet_command(action: str):
    """Dispatch wallet subcommand."""
    if action == "create":
        try:
            create_wallet_interactive()
        except RuntimeError as e:
            print(str(e))
            sys.exit(1)

    elif action == "import":
        try:
            import_wallet_interactive()
        except RuntimeError as e:
            print(str(e))
            sys.exit(1)

    elif action == "export":
        try:
            export_mnemonic_interactive()
        except RuntimeError as e:
            print(str(e))
            sys.exit(1)

    elif action == "balance":
        try:
            _balance()
        except FileNotFoundError as e:
            print(str(e))
            print("\nCreate a wallet first: alice-node wallet create")
            sys.exit(1)

    else:
        print(f"Unknown wallet action: {action}")
        sys.exit(1)
