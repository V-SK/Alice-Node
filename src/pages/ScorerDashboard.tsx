import { useEffect } from "react";
import { invoke } from "@tauri-apps/api/tauri";
import { useAppStore } from "../hooks/useAppStore";

export default function ScorerDashboard() {
  const {
    walletAddress,
    scoringState,
    setScoringState,
    networkStatus,
    addLog,
    startScorerLogListener,
  } = useAppStore();

  useEffect(() => {
    const poll = async () => {
      try {
        const status = await invoke<any>("get_scoring_status");
        setScoringState(status);
      } catch (e) {
        console.error("Failed to get scoring status:", e);
      }
    };

    const interval = setInterval(poll, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    startScorerLogListener().then((fn) => {
      unlisten = fn;
    });
    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const startScoring = async () => {
    if (!walletAddress) return;
    try {
      addLog("Starting scorer...", "info");
      await invoke("start_scoring", { walletAddress });
      addLog("Scorer started", "success");
    } catch (e: any) {
      addLog(`Failed to start scorer: ${e}`, "error");
    }
  };

  const stopScoring = async () => {
    try {
      addLog("Stopping scorer...", "info");
      await invoke("stop_scoring");
      addLog("Scorer stopped", "info");
    } catch (e: any) {
      addLog(`Failed to stop scorer: ${e}`, "error");
    }
  };

  const isRunning = scoringState.status === "Running";

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Scoring Engine</h1>
        <div className="flex items-center gap-2">
          <div className={`status-dot ${isRunning ? "" : "idle"}`} />
          <span className="text-sm text-zinc-400">{scoringState.status}</span>
        </div>
      </div>

      <div className="card">
        <div className="grid grid-cols-4 gap-6">
          {[
            ["EVALUATIONS", scoringState.evaluations],
            ["THIS EPOCH", scoringState.epoch_evals],
            ["AVG TIME", scoringState.avg_time_secs > 0 ? `${scoringState.avg_time_secs.toFixed(1)}s` : "—"],
            ["MODEL", networkStatus?.model_version ? `v${networkStatus.model_version}` : "—"],
          ].map(([label, value]) => (
            <div key={label as string}>
              <div className="text-xs text-zinc-500 mb-1">{label}</div>
              <div className="font-semibold text-lg">{value}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Accuracy</div>
          <div className="text-2xl font-bold text-green-500 font-mono">
            {scoringState.evaluations > 0
              ? (
                  ((scoringState.evaluations - scoringState.strikes) /
                    scoringState.evaluations) *
                  100
                ).toFixed(1)
              : "—"}
            {scoringState.evaluations > 0 ? "%" : ""}
          </div>
          <div className="text-xs text-zinc-500">honeypot pass rate</div>
        </div>
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Strikes</div>
          <div
            className={`text-2xl font-bold font-mono ${
              scoringState.strikes > 0 ? "text-red-500" : "text-green-500"
            }`}
          >
            {scoringState.strikes}
          </div>
          <div className="text-xs text-zinc-500">/ 20 max</div>
        </div>
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Queue</div>
          <div className="text-2xl font-bold font-mono text-zinc-200">
            {scoringState.queue_depth}
          </div>
          <div className="text-xs text-zinc-500">pending</div>
        </div>
      </div>

      <div className="card">
        <div className="text-sm text-zinc-400 mb-3">Queue Depth</div>
        <div className="progress-bar">
          <div
            className="progress-fill"
            style={{ width: `${Math.min((scoringState.queue_depth / 20) * 100, 100)}%` }}
          />
        </div>
        <div className="text-xs text-zinc-600 mt-2">{scoringState.queue_depth} / 20 max</div>
      </div>

      <div className="flex gap-3">
        {isRunning ? (
          <button onClick={stopScoring} className="btn btn-danger flex-1">
            <StopIcon />
            Stop Scoring
          </button>
        ) : (
          <button
            onClick={startScoring}
            disabled={!walletAddress}
            className="btn btn-success flex-1 disabled:opacity-50"
          >
            <PlayIcon />
            Start Scoring
          </button>
        )}
      </div>

      {scoringState.error_message && (
        <div className="card border-red-500/50 text-red-500 text-sm">
          {scoringState.error_message}
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
