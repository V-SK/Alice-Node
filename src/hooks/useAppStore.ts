import { create } from "zustand";
import { listen, UnlistenFn } from "@tauri-apps/api/event";

export type Role = "trainer" | "scorer" | "aggregator" | null;

export interface NetworkStatus {
  ps_reachable: boolean;
  ps_latency_ms: number;
  download_speed_mbps: number;
  websocket_ok: boolean;
  chain_epoch?: number;
  model_version?: number;
  issues: string[];
}

export interface GpuInfo {
  index: number;
  name: string;
  vram_total_gb: number;
  vram_free_gb: number;
  driver_version: string;
  cuda_version?: string;
  compute_capability?: string;
  is_supported: boolean;
  support_reason: string;
}

export interface MiningState {
  status: "Idle" | "Starting" | "Running" | "Stopping" | "Error";
  wallet_address?: string;
  gpu_index: number;
  current_epoch?: number;
  current_shard?: number;
  current_loss?: number;
  shards_completed: number;
  error_message?: string;
}

export interface ScoringState {
  status: "Idle" | "Starting" | "Running" | "Stopping" | "Error";
  wallet_address?: string;
  evaluations: number;
  epoch_evals: number;
  queue_depth: number;
  strikes: number;
  avg_time_secs: number;
  model_version?: number;
  error_message?: string;
}

export interface AggregatingState {
  status: "Idle" | "Starting" | "Running" | "Stopping" | "Error";
  wallet_address?: string;
  connected_miners: number;
  max_miners: number;
  gradients_received: number;
  epoch_gradients: number;
  bandwidth_mbps: number;
  model_version?: number;
  error_message?: string;
}

export interface ModelStatus {
  int8_available: boolean;
  fp16_available: boolean;
  int8_size_gb: number;
  fp16_size_gb: number;
  active_variant?: "Int8" | "Fp16";
}

interface AppState {
  // Role
  role: Role;
  setRole: (role: Role) => void;

  // Wallet
  walletAddress: string | null;
  setWalletAddress: (address: string | null) => void;

  // Network
  networkStatus: NetworkStatus | null;
  setNetworkStatus: (status: NetworkStatus | null) => void;

  // GPU
  gpuInfo: GpuInfo[];
  setGpuInfo: (info: GpuInfo[]) => void;

  // Mining
  miningState: MiningState;
  setMiningState: (state: MiningState) => void;

  // Scoring
  scoringState: ScoringState;
  setScoringState: (state: ScoringState) => void;

  // Aggregating
  aggregatingState: AggregatingState;
  setAggregatingState: (state: AggregatingState) => void;

  // Model
  modelStatus: ModelStatus | null;
  setModelStatus: (status: ModelStatus | null) => void;

  // Download
  downloadProgress: {
    variant: "Int8" | "Fp16";
    downloaded_bytes: number;
    total_bytes: number;
    percent: number;
    speed_mbps: number;
  } | null;
  setDownloadProgress: (progress: any) => void;

  // Logs
  logs: { time: string; msg: string; type: string }[];
  addLog: (msg: string, type?: string) => void;
  clearLogs: () => void;

  // Earnings
  totalEarned: number;
  epochEarned: number;
  setEarnings: (total: number, epoch: number) => void;

  // Log listeners
  startMinerLogListener: () => Promise<UnlistenFn>;
  startScorerLogListener: () => Promise<UnlistenFn>;
  startAggregatorLogListener: () => Promise<UnlistenFn>;
}

export const useAppStore = create<AppState>((set) => ({
  // Role
  role: null,
  setRole: (role) => set({ role }),

  // Wallet
  walletAddress: null,
  setWalletAddress: (address) => set({ walletAddress: address }),

  // Network
  networkStatus: null,
  setNetworkStatus: (status) => set({ networkStatus: status }),

  // GPU
  gpuInfo: [],
  setGpuInfo: (info) => set({ gpuInfo: info }),

  // Mining
  miningState: {
    status: "Idle",
    gpu_index: 0,
    shards_completed: 0,
  },
  setMiningState: (state) => set({ miningState: state }),

  // Scoring
  scoringState: {
    status: "Idle",
    evaluations: 0,
    epoch_evals: 0,
    queue_depth: 0,
    strikes: 0,
    avg_time_secs: 0,
  },
  setScoringState: (state) => set({ scoringState: state }),

  // Aggregating
  aggregatingState: {
    status: "Idle",
    connected_miners: 0,
    max_miners: 200,
    gradients_received: 0,
    epoch_gradients: 0,
    bandwidth_mbps: 0,
  },
  setAggregatingState: (state) => set({ aggregatingState: state }),

  // Model
  modelStatus: null,
  setModelStatus: (status) => set({ modelStatus: status }),

  // Download
  downloadProgress: null,
  setDownloadProgress: (progress) => set({ downloadProgress: progress }),

  // Logs
  logs: [],
  addLog: (msg, type = "info") =>
    set((state) => ({
      logs: [
        ...state.logs.slice(-99),
        {
          time: new Date().toLocaleTimeString("en-US", { hour12: false }),
          msg,
          type,
        },
      ],
    })),
  clearLogs: () => set({ logs: [] }),

  // Earnings
  totalEarned: 0,
  epochEarned: 0,
  setEarnings: (total, epoch) => set({ totalEarned: total, epochEarned: epoch }),

  // Miner log listener
  startMinerLogListener: async () => {
    return listen<{ type: string; message: string }>("miner-log", (event) => {
      const { type, message } = event.payload;
      const logType = type === "stderr" ? "error" : "info";
      useAppStore.getState().addLog(message, logType);
    });
  },

  // Scorer log listener
  startScorerLogListener: async () => {
    return listen<{ type: string; message: string }>("scorer-log", (event) => {
      const { type, message } = event.payload;
      const logType = type === "stderr" ? "error" : "info";
      useAppStore.getState().addLog(message, logType);
    });
  },

  // Aggregator log listener
  startAggregatorLogListener: async () => {
    return listen<{ type: string; message: string }>("aggregator-log", (event) => {
      const { type, message } = event.payload;
      const logType = type === "stderr" ? "error" : "info";
      useAppStore.getState().addLog(message, logType);
    });
  },
}));
