#!/usr/bin/env python3
"""
Alice Node — Shared Utilities

Common helpers used across miner, scorer, and aggregator modules.
"""

import logging
import os
import platform
import subprocess
import sys
from pathlib import Path


def setup_logging(name: str = "alice", level: str = "INFO") -> logging.Logger:
    """Configure consistent logging across all Alice Node components."""
    log_level = getattr(logging, os.environ.get("ALICE_LOG_LEVEL", level).upper(), logging.INFO)

    logger = logging.getLogger(name)
    logger.setLevel(log_level)

    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(log_level)
        fmt = logging.Formatter(
            "[%(asctime)s] %(name)s %(levelname)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        handler.setFormatter(fmt)
        logger.addHandler(handler)

    return logger


def get_alice_dir() -> Path:
    """Return the ~/.alice/ directory, creating it if needed."""
    alice_dir = Path.home() / ".alice"
    alice_dir.mkdir(parents=True, exist_ok=True)
    return alice_dir


def detect_device() -> str:
    """Auto-detect the best available compute device."""
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
    except ImportError:
        pass
    return "cpu"


def get_system_info() -> dict:
    """Gather system information for diagnostics."""
    info = {
        "os": platform.system(),
        "arch": platform.machine(),
        "python": platform.python_version(),
    }

    try:
        import torch

        info["torch"] = torch.__version__
        info["cuda_available"] = torch.cuda.is_available()
        if torch.cuda.is_available():
            info["gpu"] = torch.cuda.get_device_name(0)
            info["vram_gb"] = round(
                torch.cuda.get_device_properties(0).total_mem / (1024**3), 1
            )
        info["mps_available"] = (
            hasattr(torch.backends, "mps") and torch.backends.mps.is_available()
        )
    except ImportError:
        info["torch"] = None

    return info


def human_size(size_bytes: int) -> str:
    """Convert bytes to human-readable string."""
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(size_bytes) < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} PB"
