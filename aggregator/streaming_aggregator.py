#!/usr/bin/env python3
"""
streaming_aggregator.py — 流式梯度聚合器

边收边算，内存恒定。不管收到多少个梯度，内存不会增长。
内存占用：1 份密集梯度 (~28GB) + 计数器

备用方案，等 epoch-only 聚合验证稳定后再集成。
Created: 2026-03-21
"""
import torch
import numpy as np
import zlib
import base64
import struct
from typing import Optional, List, Tuple
import threading
import logging

log = logging.getLogger(__name__)


class StreamingAggregator:
    """
    流式梯度聚合器 — 边收边算，内存恒定

    内存占用：1 份密集梯度 (~28GB) + 计数器
    不管收到多少个梯度，内存不会增长
    """

    def __init__(self, model_shapes: dict, device: str = 'cpu', dtype=torch.float32):
        self.model_shapes = model_shapes
        self.device = device
        self.dtype = dtype
        self.accumulators: dict[str, torch.Tensor] = {}
        self.count = 0
        self.miner_ids: List[str] = []
        self._lock = threading.Lock()
        self._init_accumulators()

    def _init_accumulators(self):
        self.accumulators = {}
        for name, shape in self.model_shapes.items():
            self.accumulators[name] = torch.zeros(shape, dtype=self.dtype, device=self.device)
        self.count = 0
        self.miner_ids = []
        log.info(f"StreamingAggregator initialized: {len(self.model_shapes)} params")

    def reset(self):
        for acc in self.accumulators.values():
            acc.zero_()
        self.count = 0
        self.miner_ids = []

    SKIP_KEYS = {"dtype", "fmt"}

    def add(self, gradient_data: dict, miner_id: str = None) -> bool:
        """Add a binary_v2 compressed gradient dict to the running sum.
        
        Decompress outside the lock (CPU-bound, parallelizable).
        Only hold the lock for index_add_ (fast, <10ms).
        """
        try:
            # --- Phase 1: Decompress OUTSIDE lock ---
            global_fmt = gradient_data.get("fmt", "binary_v2")
            dtype_str = str(gradient_data.get("dtype", "torch.float16")).lower()

            if "float32" in dtype_str:
                vbytes = 4
                np_dt = np.float32
            else:
                vbytes = 2
                np_dt = np.float16

            prepared = []  # list of (name, indices, values)
            for name, data in gradient_data.items():
                if name in self.SKIP_KEYS:
                    continue
                if name not in self.accumulators:
                    continue
                if not isinstance(data, dict):
                    continue

                fmt = data.get("fmt", global_fmt)

                if fmt == "binary_v2":
                    k = int(data["k"])
                    packed = base64.b64decode(data["data"])
                    raw = zlib.decompress(packed)
                    values_np = np.frombuffer(raw[:k * vbytes], dtype=np_dt).copy()
                    indices_np = np.frombuffer(raw[k * vbytes:], dtype=np.int32).copy()
                    values = torch.from_numpy(values_np).to(dtype=self.dtype)
                    indices = torch.from_numpy(indices_np).long()
                else:
                    values = torch.tensor(data.get("values", []), dtype=self.dtype)
                    indices = torch.tensor(data.get("indices", []), dtype=torch.long)

                # NaN/Inf guard
                if torch.isnan(values).any() or torch.isinf(values).any():
                    log.warning(f"NaN/Inf in gradient from {miner_id}, param={name}, skipping")
                    del values, indices
                    continue

                if indices.numel() > 0:
                    prepared.append((name, indices, values))
                else:
                    del values, indices

            # --- Phase 2: Accumulate INSIDE lock (fast, index_add_ only) ---
            with self._lock:
                params_added = 0
                for name, indices, values in prepared:
                    acc = self.accumulators[name]
                    flat_acc = acc.view(-1)
                    indices_dev = indices.to(device=self.device)
                    values_dev = values.to(device=self.device)
                    flat_acc.index_add_(0, indices_dev, values_dev)
                    del indices_dev, values_dev, indices, values
                    params_added += 1

                self.count += 1
                if miner_id:
                    self.miner_ids.append(miner_id)

            print(f"[StreamingAgg] Added gradient #{self.count} from {miner_id}, params_added={params_added}")
            del prepared
            return True
        except Exception as e:
            log.error(f"Failed to add gradient: {e}")
            import traceback
            traceback.print_exc()
            return False

    def finalize(self) -> dict:
        with self._lock:
            if self.count == 0:
                log.warning("No gradients to aggregate")
                return {}
            result = {}
            for name, acc in self.accumulators.items():
                result[name] = acc / self.count
            log.info(f"Aggregated {self.count} gradients from {len(set(self.miner_ids))} miners")
            return result

    def get_stats(self) -> dict:
        return {
            "gradient_count": self.count,
            "unique_miners": len(set(self.miner_ids)),
            "miner_ids": list(set(self.miner_ids)),
        }


class EpochAggregationManager:
    """
    Epoch 级别的聚合管理器

    负责：
    - 维护当前 epoch 的 StreamingAggregator
    - epoch 结束时触发聚合并应用到模型
    - 导出模型和 delta
    """

    def __init__(self, model: torch.nn.Module, model_dir: str = "./models"):
        self.model = model
        self.model_dir = model_dir
        self.device = next(model.parameters()).device
        self.model_shapes = {name: param.shape for name, param in model.state_dict().items()}
        self.aggregator = StreamingAggregator(self.model_shapes, device='cpu')
        self.prev_state_dict: Optional[dict] = None
        self.model_version = 0
        self.current_epoch = 0

    def on_gradient_received(self, gradient_data: str, miner_id: str, epoch: int):
        if epoch != self.current_epoch:
            log.warning(f"Gradient from epoch {epoch}, current is {self.current_epoch}, ignoring")
            return False
        return self.aggregator.add(gradient_data, miner_id)

    def on_epoch_end(self, epoch: int, learning_rate: float = 1e-4) -> bool:
        if self.aggregator.count == 0:
            log.info(f"Epoch {epoch}: no gradients, skipping aggregation")
            self._advance_epoch(epoch)
            return False

        log.info(f"Epoch {epoch}: aggregating {self.aggregator.count} gradients...")
        averaged_grads = self.aggregator.finalize()
        self._apply_gradients(averaged_grads, learning_rate)
        self._export_model_and_delta(epoch)
        self.model_version = epoch
        self._advance_epoch(epoch)
        return True

    def _apply_gradients(self, grads: dict, lr: float):
        with torch.no_grad():
            state_dict = self.model.state_dict()
            for name, grad in grads.items():
                if name in state_dict:
                    state_dict[name] = state_dict[name].to(self.device) - lr * grad.to(self.device)
            self.model.load_state_dict(state_dict)
        log.info(f"Applied gradients with lr={lr}")

    def _export_model_and_delta(self, epoch: int):
        import os
        import io
        try:
            import zstandard as zstd
        except ImportError:
            zstd = None

        os.makedirs(self.model_dir, exist_ok=True)
        current_state = {k: v.cpu() for k, v in self.model.state_dict().items()}

        model_path = os.path.join(self.model_dir, f"model_v{epoch}.pt")
        torch.save({k: v.half() for k, v in current_state.items()}, model_path)
        model_size = os.path.getsize(model_path)
        log.info(f"Saved full model: {model_path} ({model_size / 1e9:.2f} GB)")

        if self.prev_state_dict is not None and zstd is not None:
            delta = {}
            for name, param in current_state.items():
                delta[name] = param - self.prev_state_dict[name]

            buffer = io.BytesIO()
            torch.save({k: v.half() for k, v in delta.items()}, buffer)
            compressed = zstd.compress(buffer.getvalue(), level=10)

            delta_path = os.path.join(self.model_dir, f"delta_v{epoch}.pt.zstd")
            with open(delta_path, 'wb') as f:
                f.write(compressed)

            delta_size = len(compressed)
            ratio = model_size / delta_size if delta_size > 0 else 0
            log.info(f"Saved delta: {delta_path} ({delta_size / 1e6:.1f} MB, {ratio:.1f}x smaller)")

        self.prev_state_dict = current_state
        self._cleanup_old_models(keep=10)

    def _cleanup_old_models(self, keep: int = 10):
        import os
        import glob
        model_files = sorted(glob.glob(os.path.join(self.model_dir, "model_v*.pt")))
        if len(model_files) > keep:
            for f in model_files[:-keep]:
                os.remove(f)
                log.info(f"Removed old model: {f}")
        delta_files = sorted(glob.glob(os.path.join(self.model_dir, "delta_v*.pt.zstd")))
        if len(delta_files) > keep * 2:
            for f in delta_files[:-(keep * 2)]:
                os.remove(f)

    def _advance_epoch(self, epoch: int):
        self.current_epoch = epoch + 1
        self.aggregator.reset()
