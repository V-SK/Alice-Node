#!/usr/bin/env python3
"""
Alice Node — Chain Interaction (Staking & Status)

Interacts with the Alice Protocol Substrate chain for:
    - Staking as scorer or aggregator
    - Unstaking
    - Querying staking status and rewards

Pallet: ProofOfGradient
Default RPC: wss://rpc.aliceprotocol.org
"""

import os
import sys
from pathlib import Path

DEFAULT_RPC_URL = "wss://rpc.aliceprotocol.org"
PLANCK = 10**12  # 1 ALICE = 10^12 planck

# Staking requirements (in ALICE)
STAKE_REQUIREMENTS = {
    "scorer": 5_000,
    "aggregator": 10_000,
}


def _get_substrate(rpc_url: str):
    """Connect to the Alice chain."""
    try:
        from substrateinterface import SubstrateInterface
    except ImportError:
        print("❌ substrate-interface not installed.")
        print("   Install: pip install substrate-interface")
        sys.exit(1)

    try:
        substrate = SubstrateInterface(url=rpc_url)
        return substrate
    except Exception as e:
        print(f"❌ Could not connect to chain: {e}")
        print(f"   RPC URL: {rpc_url}")
        sys.exit(1)


def _load_keypair():
    """Load keypair from wallet file (requires password)."""
    _ROOT = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(_ROOT / "miner"))

    from core.secure_wallet import unlock_wallet_interactive, DEFAULT_WALLET_PATH

    try:
        wallet = unlock_wallet_interactive()
        return wallet.to_keypair()
    except Exception as e:
        print(f"❌ Could not unlock wallet: {e}")
        sys.exit(1)


def stake(role: str, amount: float, rpc_url: str = DEFAULT_RPC_URL):
    """Stake ALICE tokens as a scorer or aggregator."""
    min_stake = STAKE_REQUIREMENTS.get(role, 0)
    if amount < min_stake:
        print(f"❌ Minimum stake for {role} is {min_stake:,} ALICE (you specified {amount:,.0f})")
        sys.exit(1)

    print(f"🔐 Staking {amount:,.0f} ALICE as {role}...")
    print(f"   RPC: {rpc_url}")
    print()

    keypair = _load_keypair()
    substrate = _get_substrate(rpc_url)

    # Map role to extrinsic
    call_map = {
        "scorer": "stake_as_scorer",
        "aggregator": "stake_as_aggregator",
    }
    call_name = call_map[role]
    amount_planck = int(amount * PLANCK)

    try:
        call = substrate.compose_call(
            call_module="ProofOfGradient",
            call_function=call_name,
            call_params={"amount": amount_planck},
        )
        extrinsic = substrate.create_signed_extrinsic(call=call, keypair=keypair)
        receipt = substrate.submit_extrinsic(extrinsic, wait_for_inclusion=True)

        if receipt.is_success:
            print(f"✅ Staked {amount:,.0f} ALICE as {role}")
            print(f"   Block: #{receipt.block_number}")
            print(f"   Extrinsic: {receipt.extrinsic_hash}")
        else:
            print(f"❌ Staking failed: {receipt.error_message}")
            sys.exit(1)

    except Exception as e:
        print(f"❌ Transaction failed: {e}")
        sys.exit(1)


def unstake(role: str, rpc_url: str = DEFAULT_RPC_URL):
    """Unstake ALICE tokens from scorer or aggregator role."""
    print(f"🔐 Unstaking from {role}...")
    print(f"   RPC: {rpc_url}")
    print()

    keypair = _load_keypair()
    substrate = _get_substrate(rpc_url)

    call_map = {
        "scorer": "unstake_scorer",
        "aggregator": "unstake_aggregator",
    }
    call_name = call_map[role]

    try:
        call = substrate.compose_call(
            call_module="ProofOfGradient",
            call_function=call_name,
            call_params={},
        )
        extrinsic = substrate.create_signed_extrinsic(call=call, keypair=keypair)
        receipt = substrate.submit_extrinsic(extrinsic, wait_for_inclusion=True)

        if receipt.is_success:
            print(f"✅ Unstaked from {role}")
            print(f"   Block: #{receipt.block_number}")
            print(f"   Tokens will be unlocked after the cooldown period.")
        else:
            print(f"❌ Unstaking failed: {receipt.error_message}")
            sys.exit(1)

    except Exception as e:
        print(f"❌ Transaction failed: {e}")
        sys.exit(1)


def status(rpc_url: str = DEFAULT_RPC_URL, address: str = None):
    """Check network status, staking info, and pending rewards."""
    substrate = _get_substrate(rpc_url)

    # If no address given, try loading from local wallet
    if not address:
        try:
            _ROOT = Path(__file__).resolve().parent.parent
            sys.path.insert(0, str(_ROOT / "miner"))
            from core.secure_wallet import load_wallet_public, DEFAULT_WALLET_PATH

            info = load_wallet_public()
            address = info["address"]
        except Exception:
            pass

    print("═══════════════════════════════════════")
    print("  Alice Protocol — Network Status")
    print("═══════════════════════════════════════")
    print()

    # Query chain info
    try:
        chain = substrate.get_chain_head()
        block = substrate.get_block_number(chain)
        print(f"  Chain:         {substrate.chain}")
        print(f"  Block:         #{block}")
        print(f"  RPC:           {rpc_url}")
    except Exception as e:
        print(f"  ⚠️  Chain query error: {e}")

    print()

    if address:
        print(f"  Address:       {address}")
        print()

        # Query balance
        try:
            account = substrate.query("System", "Account", [address])
            free = account.value["data"]["free"]
            balance = free / PLANCK
            print(f"  💰 Balance:    {balance:,.4f} ALICE")
        except Exception as e:
            print(f"  ⚠️  Balance query error: {e}")

        # Query scorer stake
        try:
            scorer_stake = substrate.query(
                "ProofOfGradient", "ScorerStakes", [address]
            )
            if scorer_stake.value:
                staked = scorer_stake.value / PLANCK
                print(f"  🛡️  Scorer:     {staked:,.0f} ALICE staked")
        except Exception:
            pass

        # Query aggregator stake
        try:
            agg_stake = substrate.query(
                "ProofOfGradient", "AggregatorStakes", [address]
            )
            if agg_stake.value:
                staked = agg_stake.value / PLANCK
                print(f"  🔗 Aggregator: {staked:,.0f} ALICE staked")
        except Exception:
            pass

        # Query pending rewards
        try:
            rewards = substrate.query(
                "ProofOfGradient", "PendingRewards", [address]
            )
            if rewards.value:
                pending = rewards.value / PLANCK
                print(f"  🎁 Rewards:    {pending:,.4f} ALICE (pending)")
        except Exception:
            pass
    else:
        print("  No address specified. Use --address or create a wallet:")
        print("    alice-node wallet create")

    print()
    print("═══════════════════════════════════════")
