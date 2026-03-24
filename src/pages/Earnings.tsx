import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/tauri";
import { useAppStore } from "../hooks/useAppStore";

interface PsStatusData {
  chain_epoch: number;
  model_version: number;
  connected_miners: number;
}

export default function Earnings() {
  const { walletAddress } = useAppStore();
  const [psStatus, setPsStatus] = useState<PsStatusData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const status = await invoke("check_ps_status");
        setPsStatus(status);
      } catch (e) {
        console.error("Failed to fetch PS status:", e);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-bold">Earnings</h1>

      {/* Network Stats from PS */}
      <div className="grid grid-cols-3 gap-4">
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Current Epoch</div>
          <div className="text-2xl font-bold text-alice-500 font-mono">
            {psStatus?.chain_epoch ?? "—"}
          </div>
        </div>
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Model Version</div>
          <div className="text-2xl font-bold text-zinc-200 font-mono">
            {psStatus?.model_version ? `v${psStatus.model_version}` : "—"}
          </div>
        </div>
        <div className="stat-card">
          <div className="text-xs text-zinc-500 mb-1">Active Miners</div>
          <div className="text-2xl font-bold text-green-500 font-mono">
            {psStatus?.connected_miners ?? "—"}
          </div>
        </div>
      </div>

      {/* Balance */}
      <div className="card">
        <h3 className="font-semibold mb-4">Balance</h3>
        <div className="text-center py-6">
          <div className="text-zinc-500 text-sm mb-2">
            {walletAddress ? (
              <span className="font-mono text-xs break-all">{walletAddress}</span>
            ) : (
              "No wallet connected"
            )}
          </div>
          <div className="text-3xl font-bold text-alice-500 font-mono mb-1">Coming soon</div>
          <div className="text-xs text-zinc-600">
            Balance query will be available when the chain launches
          </div>
        </div>
      </div>

      {/* Chart Placeholder */}
      <div className="card">
        <h3 className="font-semibold mb-4">7-Day Earnings</h3>
        <div className="h-40 flex items-end justify-around gap-2">
          {[
            { day: "Mon", h: 0 },
            { day: "Tue", h: 0 },
            { day: "Wed", h: 0 },
            { day: "Thu", h: 0 },
            { day: "Fri", h: 0 },
            { day: "Sat", h: 0 },
            { day: "Sun", h: 0 },
          ].map(({ day, h }) => (
            <div key={day} className="flex-1 flex flex-col items-center gap-2">
              <div
                className="w-full bg-gradient-to-t from-alice-600 to-alice-500 rounded-t"
                style={{ height: `${h}%` }}
              />
              <span className="text-xs text-zinc-500">{day}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Epoch History */}
      <div className="card">
        <h3 className="font-semibold mb-4">Epoch History</h3>
        {loading ? (
          <div className="text-center py-8 text-zinc-500">Loading...</div>
        ) : (
          <div className="text-center py-8 text-zinc-500">
            No earnings yet. Start mining to earn ALICE!
          </div>
        )}
      </div>
    </div>
  );
}
