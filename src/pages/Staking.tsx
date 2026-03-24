import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/tauri";
import type { StakingInfo } from "../types/tauri";
import { useAppStore } from "../hooks/useAppStore";

const STAKE_AMOUNTS: Record<string, number> = {
  scorer: 5000,
  aggregator: 20000,
};

export default function Staking() {
  const { role } = useAppStore();
  const [stakingInfo, setStakingInfo] = useState<StakingInfo>({ staked: 0, status: "None", role: null });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const requiredStake = role ? STAKE_AMOUNTS[role] ?? 0 : 0;

  const fetchInfo = async () => {
    try {
      const info = await invoke("get_staking_info");
      setStakingInfo(info);
    } catch (e) {
      console.error("Failed to get staking info:", e);
    }
  };

  useEffect(() => {
    fetchInfo();
    const interval = setInterval(fetchInfo, 10000);
    return () => clearInterval(interval);
  }, []);

  const handleStake = async () => {
    if (!confirm(`Stake ${requiredStake.toLocaleString()} ALICE as ${role}?`)) return;
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      await invoke("stake", { amount: requiredStake });
      setMessage("Stake submitted. Status will update shortly.");
      await fetchInfo();
    } catch (e: any) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  };

  const handleUnstake = async () => {
    if (!confirm("Unstake? There is a 7-day cooldown before funds are returned.")) return;
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      await invoke("unstake");
      setMessage("Unstake submitted. Funds will be available after the 7-day cooldown.");
      await fetchInfo();
    } catch (e: any) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  };

  const isActive = stakingInfo.status === "Active";
  const isPending = stakingInfo.status === "Pending";

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-bold">Staking</h1>

      <div className="card">
        <div className="text-xs text-zinc-500 mb-3">STAKING STATUS</div>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-3xl font-bold font-mono text-alice-500">
              {stakingInfo.staked.toLocaleString()}
            </div>
            <div className="text-xs text-zinc-500 mt-1">ALICE staked</div>
          </div>
          <div
            className={`px-3 py-1 rounded-full text-sm font-semibold ${
              isActive
                ? "bg-green-500/20 text-green-500"
                : isPending
                ? "bg-yellow-500/20 text-yellow-500"
                : "bg-zinc-800 text-zinc-500"
            }`}
          >
            {stakingInfo.status}
          </div>
        </div>
      </div>

      <div className="card space-y-4">
        <div className="text-sm font-semibold text-zinc-300">
          Required stake for {role ? role.charAt(0).toUpperCase() + role.slice(1) : "—"}
        </div>
        <div className="flex items-center justify-between py-2 border-b border-zinc-800">
          <span className="text-sm text-zinc-400">Minimum</span>
          <span className="font-mono text-alice-500">{requiredStake.toLocaleString()} ALICE</span>
        </div>
        <div className="flex items-center justify-between py-2">
          <span className="text-sm text-zinc-400">Currently staked</span>
          <span className="font-mono text-zinc-300">{stakingInfo.staked.toLocaleString()} ALICE</span>
        </div>

        {error && (
          <div className="text-red-500 text-sm bg-red-500/10 rounded-lg px-3 py-2">{error}</div>
        )}
        {message && (
          <div className="text-green-500 text-sm bg-green-500/10 rounded-lg px-3 py-2">
            {message}
          </div>
        )}

        <div className="flex gap-3 pt-2">
          {!isActive && !isPending && (
            <button
              onClick={handleStake}
              disabled={loading || requiredStake === 0}
              className="btn btn-primary flex-1 disabled:opacity-50"
            >
              {loading ? "Processing..." : `Stake ${requiredStake.toLocaleString()} ALICE`}
            </button>
          )}
          {(isActive || isPending) && (
            <button
              onClick={handleUnstake}
              disabled={loading}
              className="btn btn-danger flex-1 disabled:opacity-50"
            >
              {loading ? "Processing..." : "Unstake (7-day cooldown)"}
            </button>
          )}
        </div>
      </div>

      <div className="card text-sm text-zinc-500 space-y-2">
        <div className="font-semibold text-zinc-400">How staking works</div>
        <div>Stake ALICE tokens to activate your node role on-chain.</div>
        <div>Staked tokens are locked while your node is active.</div>
        <div>Unstaking initiates a 7-day cooldown before tokens are returned.</div>
        <div>Nodes with bad behavior may be slashed during the review window.</div>
      </div>
    </div>
  );
}
