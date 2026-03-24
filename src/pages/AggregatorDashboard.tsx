import { useEffect } from "react";
import { invoke } from "@tauri-apps/api/tauri";
import { useAppStore } from "../hooks/useAppStore";

export default function AggregatorDashboard() {
  const {
    walletAddress,
    aggregatingState,
    setAggregatingState,
    networkStatus,
    addLog,
    startAggregatorLogListener,
  } = useAppStore();

  useEffect(() => {
    const poll = async () => {
      try {
        const status = await invoke("get_aggregating_status");
        setAggregatingState(status);
      } catch (e) {
        console.error("Failed to get aggregating status:", e);
      }
    };

    const interval = setInterval(poll, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    startAggregatorLogListener().then((fn) => {
      unlisten = fn;
    });
    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const startAggregating = async () => {
    if (!walletAddress) return;
    try {
      addLog("Starting aggregator...", "info");
      await invoke("start_aggregating", { walletAddress });
      addLog("Aggregator started", "success");
    } catch (e: any) {
      addLog(`Failed to start aggregator: ${e}`, "error");
    }
  };

  const stopAggregating = async () => {
    try {
      addLog("Stopping aggregator...", "info");
      await invoke("stop_aggregating");
      addLog("Aggregator stopped", "info");
    } catch (e: any) {
      addLog(`Failed to stop aggregator: ${e}`, "error");
    }
  };

  const isRunning = aggregatingState.status === "Running";
  const capacityPct = aggregatingState.max_miners > 0
    ? (aggregatingState.connected_miners / aggregatingState.max_miners) * 100
    : 0;

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Aggregation Node</h1>
        <div className="flex items-center gap-2">
          <div className={`status-dot ${isRunning ? "" : "idle"}`} />
          <span className="text-sm text-zinc-400">{aggregatingState.status}</span>
        </div>
      </div>

      <div className="card">
        <div className="grid grid-cols-4 gap-6 mb-6">
          {[
            ["MINERS", `${aggregatingState.connected_miners}/${aggregatingState.max_miners}`],
            ["GRADIENTS", aggregatingState.gradients_received],
            ["BANDWIDTH", aggregatingState.bandwidth_mbps > 0 ? `${aggregatingState.bandwidth_mbps.toFixed(0)} Mbps` : "—"],
            ["MODEL", networkStatus?.model_version ? `v${networkStatus.model_version}` : "—"],
          ].map(([label, value]) => (
            <div key={label as string}>
              <div className="text-xs text-zinc-500 mb-1">{label}</div>
              <div className="font-semibold text-lg">{value}</div>
            </div>
          ))}
        </div>

        <div>
          <div className="flex justify-between text-xs text-zinc-500 mb-2">
            <span>Node Capacity</span>
            <span className="font-mono text-alice-500">{capacityPct.toFixed(0)}%</span>
          </div>
          <div className="progress-bar h-2">
            <div className="progress-fill" style={{ width: `${capacityPct}%` }} />
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">This Epoch</div>
          <div className="text-2xl font-bold text-alice-500 font-mono">
            {aggregatingState.epoch_gradients}
          </div>
          <div className="text-xs text-zinc-500">gradients</div>
        </div>
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Epoch</div>
          <div className="text-2xl font-bold font-mono text-zinc-200">
            {networkStatus?.chain_epoch ?? "—"}
          </div>
          <div className="text-xs text-zinc-500">current</div>
        </div>
      </div>

      <div className="flex gap-3">
        {isRunning ? (
          <button onClick={stopAggregating} className="btn btn-danger flex-1">
            <StopIcon />
            Stop Aggregating
          </button>
        ) : (
          <button
            onClick={startAggregating}
            disabled={!walletAddress}
            className="btn btn-success flex-1 disabled:opacity-50"
          >
            <PlayIcon />
            Start Aggregating
          </button>
        )}
      </div>

      {aggregatingState.error_message && (
        <div className="card border-red-500/50 text-red-500 text-sm">
          {aggregatingState.error_message}
        </div>
      )}
    </div>
  );
}

function PlayIcon() {
  return (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M8 5v14l11-7z" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <rect x="6" y="6" width="12" height="12" rx="2" />
    </svg>
  );
}
