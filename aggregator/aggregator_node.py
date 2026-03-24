#!/usr/bin/env python3
"""
aggregator_node.py — Alice Aggregator Node

Independent service that handles miner-facing operations:
- Miner registration & task assignment
- Gradient reception & streaming aggregation
- Shard & model serving
- Score sampling → scorer → PS reporting

PS becomes pure control plane: epoch lifecycle, chain submission, model updates.

Miners connect to aggregator nodes directly — same API endpoints, no miner code changes.

Created: 2026-03-23
"""

import os
import io
import time
import json
import random
import secrets
import threading
import logging
import argparse
import zlib

import requests
import torch
import numpy as np
from pathlib import Path
from flask import Flask, request, jsonify, send_file, make_response, Response

from streaming_aggregator import StreamingAggregator

log = logging.getLogger("aggregator")


class AggregatorNode:
    def __init__(self, config):
        self.node_id = config.get("node_id", "agg-1")
        self.ps_url = config.get("ps_url", "http://127.0.0.1:8083")
        self.endpoint = config.get("endpoint", "")  # Our public URL
        self.max_miners = config.get("max_miners", 200)
        self.data_dir = Path(config.get("data_dir", "./data/shards"))
        self.model_dir = Path(config.get("model_dir", "./models"))
        self.scorer_endpoint = config.get("scorer_endpoint", "")
        self.scorer_api_key = config.get("scorer_api_key", "")
        self.scoring_ratio = config.get("scoring_ratio", 0.10)

        # Miner management
        self.miners = {}  # {miner_id: {"address", "capabilities", "registered_at", "auth_token", "last_seen"}}
        self.miners_lock = threading.Lock()

        # Aggregation
        self.streaming_agg = None  # Initialized when model loaded
        self.model_shapes = {}
        self.model_version = 0

        # Epoch state
        self.current_epoch = 0
        self.epoch_start_time = time.time()
        self.epoch_contributions = []
        self.epoch_shard_count = 0
        self.epoch_gradient_count = 0

        # Scoring
        self.scorer_eval_counts = {}

        # PS communication
        self._ps_lock = threading.Lock()

        # Delta cache
        self._delta_cache = None
        self._delta_lock = threading.Lock()

        log.info(f"[INIT] AggregatorNode {self.node_id} created")

    # ============================================
    # Miner-facing endpoints
    # ============================================

    def handle_register(self, request_data):
        """Miner registration."""
        address = request_data.get("address", "")
        capabilities = request_data.get("capabilities", {})

        mem_gb = capabilities.get("memory_gb", 0)
        if mem_gb < 20:
            return {"status": "rejected", "reason": f"Insufficient memory: {mem_gb}GB < 20GB"}, 400

        token = secrets.token_urlsafe(32)
        miner_id = address[:16] if address else f"miner_{secrets.token_hex(8)}"

        # Determine layer assignment based on memory
        if mem_gb >= 24:
            layers = list(range(32))
        elif mem_gb >= 16:
            layers = list(range(0, 8))  # First 8 layers for 16GB
        else:
            layers = list(range(0, 4))

        with self.miners_lock:
            if len(self.miners) >= self.max_miners:
                return {"status": "full", "message": f"Node full ({self.max_miners} miners)"}, 503

            self.miners[miner_id] = {
                "address": address,
                "capabilities": capabilities,
                "registered_at": time.time(),
                "auth_token": token,
                "last_seen": time.time(),
                "assigned_layers": layers,
            }

        log.info(f"[REGISTER] {miner_id} ({address[:12]}...) mem={mem_gb}GB layers={len(layers)} miners={len(self.miners)}")

        return {
            "status": "ok",
            "miner_id": miner_id,
            "token": token,
            "assigned_layers": layers,
            "model_version": self.model_version,
        }, 200

    def handle_task_request(self, request_data, miner_id):
        """Assign a shard to miner."""
        if self.streaming_agg is None:
            return {"status": "not_ready", "reason": "Epoch not started"}, 503

        # Random shard from training set (0-59950), exclude validation (59951-60000)
        shard_id = random.randint(0, 59950)
        task_id = f"{miner_id}_{shard_id}_{int(time.time())}"
        task_nonce = secrets.token_hex(8)

        miner_info = self.miners.get(miner_id, {})
        layers = miner_info.get("assigned_layers", list(range(32)))

        return {
            "status": "ok",
            "task_id": task_id,
            "task_nonce": task_nonce,
            "shard_id": shard_id,
            "assigned_layers": layers,
            "model_version": self.model_version,
        }, 200

    def handle_task_complete(self, request_data, miner_id):
        """Receive gradient, add to streaming accumulator."""
        if self.streaming_agg is None:
            return {"status": "not_ready"}, 503

        gradient_data = request_data.get("gradients", {})
        metrics = request_data.get("metrics", {})
        shard_id = metrics.get("shard_id", -1)
        task_id = request_data.get("task_id", "")

        # Add to aggregator
        try:
            self.streaming_agg.add(gradient_data, miner_id=miner_id)
            self.epoch_gradient_count += 1
            self.epoch_shard_count += 1
        except Exception as e:
            log.error(f"[AGG] add failed: {e}")
            return {"status": "error", "reason": str(e)}, 500

        # Record contribution
        self.epoch_contributions.append({
            "miner_id": miner_id,
            "address": self.miners.get(miner_id, {}).get("address", ""),
            "shard_id": shard_id,
            "timestamp": time.time(),
        })

        # Sample for scoring (configurable ratio, default 10%)
        if self.scorer_endpoint and random.random() < self.scoring_ratio:
            threading.Thread(
                target=self._send_to_scorer,
                args=(gradient_data, miner_id, shard_id, task_id),
                daemon=True,
            ).start()

        log.info(
            f"[GRADIENT] {miner_id[:16]} shard={shard_id} "
            f"total={self.epoch_gradient_count} agg_count={self.streaming_agg.count}"
        )

        return {
            "status": "accepted",
            "task_id": task_id,
            "model_version": self.model_version,
        }, 200

    def handle_shard_download(self, shard_id):
        """Shard download — X-Accel-Redirect for nginx or direct send."""
        filename = f"shard_{shard_id:06d}.pt"
        filepath = self.data_dir / filename

        if not filepath.exists():
            return jsonify({"status": "not_found", "shard_id": shard_id}), 404

        # nginx X-Accel-Redirect (zero-copy sendfile)
        response = make_response()
        response.headers["X-Accel-Redirect"] = f"/internal_shards/{filename}"
        response.headers["Content-Type"] = "application/octet-stream"
        response.headers["Cache-Control"] = "public, max-age=300"
        return response

    def handle_model_info(self):
        """Return current model version info."""
        return {
            "model_version": self.model_version,
            "download_url": f"/models/v{self.model_version}_full.pt",
        }, 200

    def handle_model_delta(self, from_version):
        """Return model delta from given version."""
        with self._delta_lock:
            if self._delta_cache and self._delta_cache.get("from_version") == from_version:
                return self._delta_cache, 200

        # Proxy to PS for delta
        try:
            resp = requests.get(
                f"{self.ps_url}/model/delta",
                params={"from_version": from_version},
                timeout=120,
            )
            if resp.status_code == 200:
                data = resp.json()
                with self._delta_lock:
                    self._delta_cache = data
                return data, 200
            return {"status": "no_delta"}, resp.status_code
        except Exception as e:
            return {"status": "error", "reason": str(e)}, 502

    # ============================================
    # Scorer communication
    # ============================================

    def _send_to_scorer(self, gradient_data, miner_id, shard_id, task_id):
        """Forward gradient to scorer for evaluation, report result to PS."""
        try:
            headers = {}
            if self.scorer_api_key:
                headers["Authorization"] = f"Bearer {self.scorer_api_key}"

            resp = requests.post(
                f"{self.scorer_endpoint}/score",
                json={
                    "gradients": gradient_data,
                    "shard_id": shard_id,
                    "miner_id": miner_id,
                },
                headers=headers,
                timeout=60,
            )
            if resp.status_code == 200:
                result = resp.json()
                score = result.get("score", 0)
                self._report_score_to_ps(miner_id, score, shard_id, task_id)
                scorer_id = result.get("scorer_address", "local")
                self.scorer_eval_counts[scorer_id] = self.scorer_eval_counts.get(scorer_id, 0) + 1
                log.info(f"[SCORE] {miner_id[:16]} score={score:.6f} shard={shard_id}")
            else:
                log.warning(f"[SCORE] scorer returned {resp.status_code}")
        except Exception as e:
            log.warning(f"[SCORE] failed: {e}")

    def _report_score_to_ps(self, miner_id, score, shard_id, task_id):
        """Report score to PS for reward calculation."""
        try:
            address = self.miners.get(miner_id, {}).get("address", "")
            requests.post(
                f"{self.ps_url}/epoch/scores",
                json={
                    "node_id": self.node_id,
                    "miner_id": miner_id,
                    "address": address,
                    "score": score,
                    "shard_id": shard_id,
                    "task_id": task_id,
                    "epoch": self.current_epoch,
                },
                timeout=10,
            )
        except Exception as e:
            log.warning(f"[PS] score report failed: {e}")

    # ============================================
    # PS communication — Epoch lifecycle
    # ============================================

    def _epoch_sync_loop(self):
        """Background thread: sync epoch state with PS."""
        while True:
            try:
                resp = requests.get(f"{self.ps_url}/epoch/status", timeout=10)
                if resp.status_code == 200:
                    status = resp.json()
                    ps_epoch = status.get("epoch", 0)

                    if ps_epoch > self.current_epoch:
                        log.info(f"[EPOCH] PS epoch {ps_epoch} > local {self.current_epoch}, transitioning...")
                        self._handle_epoch_end()
                        self._start_new_epoch(ps_epoch)

                    # Check for model updates
                    ps_model_v = status.get("model_version", 0)
                    if ps_model_v > self.model_version:
                        self._pull_model_delta(ps_model_v)

            except Exception as e:
                log.warning(f"[EPOCH SYNC] failed: {e}")

            time.sleep(30)

    def _handle_epoch_end(self):
        """Epoch end: finalize aggregation + submit to PS."""
        if self.streaming_agg is None or self.streaming_agg.count == 0:
            log.info(f"[EPOCH {self.current_epoch}] No gradients to submit")
            return

        log.info(
            f"[EPOCH {self.current_epoch}] Ending: "
            f"{self.epoch_gradient_count} gradients, {len(self.miners)} miners"
        )

        # Finalize
        try:
            averaged = self.streaming_agg.finalize()
        except Exception as e:
            log.error(f"[EPOCH] finalize failed: {e}")
            self.streaming_agg.reset()
            return

        # Compress and send to PS
        try:
            buffer = io.BytesIO()
            torch.save(averaged, buffer)
            compressed = zlib.compress(buffer.getvalue(), level=1)
            del buffer  # Free memory

            resp = requests.post(
                f"{self.ps_url}/epoch/result",
                data=compressed,
                headers={
                    "Content-Type": "application/octet-stream",
                    "X-Node-Id": self.node_id,
                    "X-Epoch": str(self.current_epoch),
                    "X-Miner-Count": str(len(self.miners)),
                    "X-Gradient-Count": str(self.epoch_gradient_count),
                    "X-Shard-Count": str(self.epoch_shard_count),
                },
                timeout=300,
            )
            if resp.status_code == 200:
                log.info(
                    f"[EPOCH {self.current_epoch}] Result submitted to PS: "
                    f"{len(compressed)/1e6:.1f}MB compressed"
                )
            else:
                log.error(f"[EPOCH {self.current_epoch}] PS rejected result: {resp.status_code}")

            del compressed
        except Exception as e:
            log.error(f"[EPOCH] submit failed: {e}")

        # Reset aggregator
        self.streaming_agg.reset()

    def _start_new_epoch(self, epoch_number):
        """Start new epoch."""
        self.current_epoch = epoch_number
        self.epoch_start_time = time.time()
        self.epoch_contributions = []
        self.epoch_shard_count = 0
        self.epoch_gradient_count = 0
        self.scorer_eval_counts = {}

        log.info(f"[EPOCH {self.current_epoch}] Started, {len(self.miners)} miners")

    def _pull_model_delta(self, target_version):
        """Pull model delta from PS."""
        try:
            resp = requests.get(
                f"{self.ps_url}/model/delta",
                params={"from_version": self.model_version},
                timeout=120,
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get("status") == "ok":
                    self.model_version = target_version
                    with self._delta_lock:
                        self._delta_cache = data
                    log.info(f"[MODEL] Updated to v{self.model_version}")
            elif resp.status_code == 304:
                log.info("[MODEL] Already up to date")
        except Exception as e:
            log.warning(f"[MODEL] delta pull failed: {e}")

    # ============================================
    # Initialization
    # ============================================

    def initialize(self):
        """Startup: download model, connect to PS, init aggregator."""
        log.info(f"[INIT] Aggregator node {self.node_id} starting...")
        log.info(f"[INIT] PS: {self.ps_url}")
        log.info(f"[INIT] Scorer: {self.scorer_endpoint or 'none'}")
        log.info(f"[INIT] Max miners: {self.max_miners}")
        log.info(f"[INIT] Data dir: {self.data_dir}")

        # Register with PS
        try:
            resp = requests.post(
                f"{self.ps_url}/node/register",
                json={
                    "node_id": self.node_id,
                    "endpoint": self.endpoint,
                    "max_miners": self.max_miners,
                },
                timeout=30,
            )
            if resp.status_code == 200:
                data = resp.json()
                self.current_epoch = data.get("current_epoch", 0)
                self.model_version = data.get("model_version", 0)
                log.info(f"[INIT] Registered with PS, epoch={self.current_epoch}, model=v{self.model_version}")
        except Exception as e:
            log.warning(f"[INIT] PS registration failed: {e}, will retry in sync loop")

        # Get model shapes from PS
        try:
            resp = requests.get(f"{self.ps_url}/model/info", timeout=30)
            if resp.status_code == 200:
                info = resp.json()
                self.model_version = info.get("model_version", self.model_version)
                # Model shapes needed for StreamingAggregator
                shapes = info.get("model_shapes", {})
                if shapes:
                    self.model_shapes = {k: tuple(v) for k, v in shapes.items()}
        except Exception as e:
            log.warning(f"[INIT] Failed to get model info: {e}")

        # Initialize aggregator
        if self.model_shapes:
            self.streaming_agg = StreamingAggregator(
                model_shapes=self.model_shapes,
                device="cpu",
                dtype=torch.float32,
            )
            log.info(f"[INIT] StreamingAggregator initialized: {len(self.model_shapes)} params")
        else:
            log.warning("[INIT] No model shapes, aggregator not initialized (will retry on first epoch sync)")

        # Start epoch sync loop
        threading.Thread(target=self._epoch_sync_loop, daemon=True, name="epoch_sync").start()

        # Start miner cleanup loop
        threading.Thread(target=self._miner_cleanup_loop, daemon=True, name="miner_cleanup").start()

        log.info("[INIT] ✅ Aggregator node ready")

    def _miner_cleanup_loop(self):
        """Remove miners that haven't been seen in 5 minutes."""
        while True:
            time.sleep(60)
            now = time.time()
            with self.miners_lock:
                stale = [
                    mid for mid, info in self.miners.items()
                    if now - info.get("last_seen", 0) > 300
                ]
                for mid in stale:
                    del self.miners[mid]
                    log.info(f"[CLEANUP] Removed stale miner {mid}")


# ============================================
# Flask App
# ============================================

def create_app(config=None):
    """Create Flask app with aggregator node."""
    if config is None:
        config = {
            "node_id": os.environ.get("AGG_NODE_ID", "agg-1"),
            "ps_url": os.environ.get("AGG_PS_URL", "http://127.0.0.1:8083"),
            "endpoint": os.environ.get("AGG_ENDPOINT", ""),
            "max_miners": int(os.environ.get("AGG_MAX_MINERS", "200")),
            "data_dir": os.environ.get("AGG_DATA_DIR", "./data/shards"),
            "model_dir": os.environ.get("AGG_MODEL_DIR", "./models"),
            "scorer_endpoint": os.environ.get("AGG_SCORER_ENDPOINT", ""),
            "scorer_api_key": os.environ.get("SCORER_API_KEY", ""),
            "scoring_ratio": float(os.environ.get("AGG_SCORING_RATIO", "0.10")),
        }

    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 50 * 1024 * 1024  # 50MB
    node = AggregatorNode(config)

    # ── Auth helper ──
    def _auth_miner(req):
        """Authenticate miner by Bearer token."""
        token = req.headers.get("Authorization", "").replace("Bearer ", "")
        if not token:
            return None
        with node.miners_lock:
            for mid, info in node.miners.items():
                if info.get("auth_token") == token:
                    info["last_seen"] = time.time()
                    return mid
        return None

    # ── Miner endpoints (same API as PS — no miner code changes) ──

    @app.route("/register", methods=["POST"])
    def register():
        result, code = node.handle_register(request.json)
        return jsonify(result), code

    @app.route("/task/request", methods=["POST"])
    def task_request():
        miner_id = _auth_miner(request)
        if not miner_id:
            return jsonify({"error": "unauthorized"}), 403
        result, code = node.handle_task_request(request.json, miner_id)
        return jsonify(result), code

    @app.route("/task/complete", methods=["POST"])
    def task_complete():
        miner_id = _auth_miner(request)
        if not miner_id:
            return jsonify({"error": "unauthorized"}), 403
        result, code = node.handle_task_complete(request.json, miner_id)
        return jsonify(result), code

    @app.route("/task/shard/<int:shard_id>", methods=["GET"])
    def shard_download(shard_id):
        return node.handle_shard_download(shard_id)

    @app.route("/model/info", methods=["GET"])
    def model_info():
        result, code = node.handle_model_info()
        return jsonify(result), code

    @app.route("/model/delta", methods=["GET"])
    def model_delta():
        from_version = request.args.get("from_version", 0, type=int)
        result, code = node.handle_model_delta(from_version)
        return jsonify(result), code

    @app.route("/model", methods=["GET"])
    def model_download():
        """Model file download — nginx X-Accel-Redirect."""
        v = node.model_version
        response = make_response()
        response.headers["X-Accel-Redirect"] = f"/internal_models/v{v}_full.pt"
        response.headers["Content-Type"] = "application/octet-stream"
        return response

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify({
            "status": "ok",
            "node_id": node.node_id,
            "miners": len(node.miners),
            "max_miners": node.max_miners,
            "epoch": node.current_epoch,
            "gradients": node.epoch_gradient_count,
            "model_version": node.model_version,
        })

    @app.route("/status", methods=["GET"])
    def status():
        return jsonify({
            "node_id": node.node_id,
            "ps_url": node.ps_url,
            "miners": len(node.miners),
            "max_miners": node.max_miners,
            "epoch": node.current_epoch,
            "epoch_gradients": node.epoch_gradient_count,
            "epoch_shards": node.epoch_shard_count,
            "model_version": node.model_version,
            "scorer_evals": sum(node.scorer_eval_counts.values()),
            "uptime": time.time() - node.epoch_start_time,
            "contributions": len(node.epoch_contributions),
        })

    # Initialize in background
    threading.Thread(target=node.initialize, daemon=True, name="init").start()

    return app


# ============================================
# CLI entry point
# ============================================

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    parser = argparse.ArgumentParser(description="Alice Aggregator Node")
    parser.add_argument("--node-id", default="agg-1")
    parser.add_argument("--ps-url", required=True, help="Parameter Server URL")
    parser.add_argument("--endpoint", default="", help="Our public endpoint URL")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8084)
    parser.add_argument("--max-miners", type=int, default=200)
    parser.add_argument("--data-dir", default="./data/shards")
    parser.add_argument("--model-dir", default="./models")
    parser.add_argument("--scorer-endpoint", default="")
    parser.add_argument("--scoring-ratio", type=float, default=0.10)
    args = parser.parse_args()

    config = vars(args)
    config["scorer_api_key"] = os.environ.get("SCORER_API_KEY", "")

    app = create_app(config)
    app.run(host=args.host, port=args.port, threaded=True)
