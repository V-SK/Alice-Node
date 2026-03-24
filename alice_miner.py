#!/usr/bin/env python3
"""
Alice Miner Client — Backward Compatibility Wrapper

⚠️  DEPRECATED: This file is kept for backward compatibility.
    Use 'python alice_node.py mine' instead.

    This wrapper delegates to miner/alice_miner.py.
"""
import sys
import os
import warnings

warnings.warn(
    "\n"
    "╔════════════════════════════════════════════════════════════╗\n"
    "║  alice_miner.py is deprecated.                            ║\n"
    "║  Use: python alice_node.py mine                           ║\n"
    "║  This wrapper will be removed in a future release.        ║\n"
    "╚════════════════════════════════════════════════════════════╝",
    DeprecationWarning,
    stacklevel=1,
)

# Add miner/ to path so imports resolve
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "miner"))

from alice_miner import main  # noqa: E402

if __name__ == "__main__":
    main()
