import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/tauri";

interface SetupProps {
  onComplete: (address: string, role: string) => void;
}

type Step = "welcome" | "network" | "gpu" | "model" | "wallet" | "role" | "ready";

export default function Setup({ onComplete }: SetupProps) {
  const [step, setStep] = useState<Step>("welcome");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Role
  const [selectedRole, setSelectedRole] = useState<string | null>(null);

  // Network check
  const [networkOk, setNetworkOk] = useState(false);
  const [networkStatus, setNetworkStatus] = useState<any>(null);
  
  // GPU check
  const [gpus, setGpus] = useState<any[]>([]);
  const [selectedGpu, setSelectedGpu] = useState(0);
  
  // Model download
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [downloadStatus, setDownloadStatus] = useState<string>("");
  
  // Wallet
  const [walletAddress, setWalletAddress] = useState("");
  const [mnemonic, setMnemonic] = useState("");
  const [showMnemonic, setShowMnemonic] = useState(false);
  const [importMode, setImportMode] = useState(false);
  const [importMnemonic, setImportMnemonic] = useState("");

  // Network check
  const checkNetwork = async () => {
    setLoading(true);
    setError(null);
    try {
      const status = await invoke("diagnose_network");
      setNetworkStatus(status);
      setNetworkOk(status.ps_reachable && status.websocket_ok);
      if (status.ps_reachable) {
        setStep("gpu");
      }
    } catch (e: any) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  };

  // GPU check
  const checkGpu = async () => {
    setLoading(true);
    try {
      const detected = await invoke("detect_gpu");
      setGpus(detected);
      const supported = detected.find((g) => g.is_supported);
      if (supported) {
        setSelectedGpu(supported.index);
      }
    } catch (e: any) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (step === "gpu") {
      checkGpu();
    }
  }, [step]);

  // Model download
  const downloadModel = async () => {
    setLoading(true);
    setDownloadStatus("Starting download...");
    try {
      // Check current status
      const status = await invoke("check_model_status");
      if (status.int8_available || status.fp16_available) {
        setDownloadStatus("Model already downloaded");
        setDownloadProgress(100);
        setTimeout(() => setStep("wallet"), 1000);
        return;
      }

      // Start download
      await invoke("download_model", { variant: "Int8" });
      
      // Poll progress
      const pollProgress = async () => {
        const progress = await invoke("get_download_progress");
        if (progress) {
          setDownloadProgress(progress.percent);
          setDownloadStatus(
            `Downloading: ${(progress.downloaded_bytes / 1e9).toFixed(2)} / ${(
              progress.total_bytes / 1e9
            ).toFixed(2)} GB`
          );
          if (progress.percent < 100) {
            setTimeout(pollProgress, 500);
          } else {
            setDownloadStatus("Download complete!");
            setTimeout(() => setStep("wallet"), 1000);
          }
        }
      };
      pollProgress();
    } catch (e: any) {
      setError(e.toString());
      setLoading(false);
    }
  };

  // Wallet creation
  const createWallet = async () => {
    setLoading(true);
    try {
      const wallet = await invoke("generate_wallet");
      setWalletAddress(wallet.address);
      setMnemonic(wallet.mnemonic);
      setShowMnemonic(true);
    } catch (e: any) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  };

  const importWallet = async () => {
    setLoading(true);
    try {
      const wallet = await invoke("import_wallet", {
        mnemonic: importMnemonic.trim(),
      });
      setWalletAddress(wallet.address);
      await saveAndFinish(wallet.address);
    } catch (e: any) {
      setError("Invalid mnemonic phrase");
    } finally {
      setLoading(false);
    }
  };

  const saveAndFinish = async (address: string) => {
    await invoke("save_wallet_address", { address });
    setMnemonic("");
    setShowMnemonic(false);
    setStep("role");
  };

  // Render steps
  const renderStep = () => {
    switch (step) {
      case "welcome":
        return (
          <div className="text-center">
            <div className="w-24 h-24 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-alice-500 to-alice-600 flex items-center justify-center animate-breathe">
              <svg viewBox="0 0 1024 1024" className="w-14 h-14 fill-white">
                <path d="M471.24 165.64 166.68 821.56c-10.92 23.76 6.24 50.84 32.24 50.84h116.96c12.48 0 23.92-7.28 29.12-18.64L512 520.32l166.96 333.44c5.24 11.36 16.68 18.64 29.12 18.64h116.96c26 0 43.2-27.08 32.28-50.84L552.76 165.64c-8.32-18.04-34.2-18.04-42.52 0l-39 84.88z" />
              </svg>
            </div>
            <h1 className="text-3xl font-bold mb-3">Welcome to Alice Miner</h1>
            <p className="text-zinc-400 mb-8 max-w-md mx-auto">
              Join the decentralized AI training network. Contribute your GPU power
              and earn ALICE tokens.
            </p>
            <button
              onClick={() => setStep("network")}
              className="btn btn-primary text-lg px-8 py-3"
            >
              Get Started
            </button>
          </div>
        );

      case "network":
        return (
          <div className="text-center">
            <h2 className="text-2xl font-bold mb-6">Network Check</h2>
            {loading ? (
              <div className="flex flex-col items-center gap-4">
                <div className="w-12 h-12 border-4 border-alice-500 border-t-transparent rounded-full animate-spin" />
                <p className="text-zinc-400">Checking connection to Parameter Server...</p>
              </div>
            ) : networkStatus ? (
              <div className="space-y-4 max-w-md mx-auto text-left">
                <div className="card">
                  <div className="flex items-center justify-between mb-2">
                    <span>PS Connection</span>
                    <span className={networkStatus.ps_reachable ? "text-green-500" : "text-red-500"}>
                      {networkStatus.ps_reachable ? "✓ Connected" : "✗ Failed"}
                    </span>
                  </div>
                  {networkStatus.ps_reachable && (
                    <div className="text-sm text-zinc-500">
                      Latency: {networkStatus.ps_latency_ms}ms
                    </div>
                  )}
                </div>
                <div className="card">
                  <div className="flex items-center justify-between mb-2">
                    <span>WebSocket</span>
                    <span className={networkStatus.websocket_ok ? "text-green-500" : "text-red-500"}>
                      {networkStatus.websocket_ok ? "✓ OK" : "✗ Failed"}
                    </span>
                  </div>
                </div>
                <div className="card">
                  <div className="flex items-center justify-between">
                    <span>Download Speed</span>
                    <span className="text-zinc-300">
                      {networkStatus.download_speed_mbps.toFixed(1)} Mbps
                    </span>
                  </div>
                </div>
                {networkStatus.issues.length > 0 && (
                  <div className="card border-yellow-500/50">
                    <div className="text-yellow-500 text-sm">
                      {networkStatus.issues.map((issue: string, i: number) => (
                        <div key={i}>⚠ {issue}</div>
                      ))}
                    </div>
                  </div>
                )}
                <div className="flex gap-3 pt-4">
                  <button onClick={checkNetwork} className="btn btn-secondary flex-1">
                    Retry
                  </button>
                  <button
                    onClick={() => setStep("gpu")}
                    disabled={!networkOk}
                    className="btn btn-primary flex-1 disabled:opacity-50"
                  >
                    Continue
                  </button>
                </div>
              </div>
            ) : (
              <button onClick={checkNetwork} className="btn btn-primary">
                Check Network
              </button>
            )}
          </div>
        );

      case "gpu":
        return (
          <div className="text-center">
            <h2 className="text-2xl font-bold mb-6">GPU Detection</h2>
            {loading ? (
              <div className="flex flex-col items-center gap-4">
                <div className="w-12 h-12 border-4 border-alice-500 border-t-transparent rounded-full animate-spin" />
                <p className="text-zinc-400">Detecting GPUs...</p>
              </div>
            ) : (
              <div className="space-y-4 max-w-md mx-auto">
                {gpus.map((gpu) => (
                  <div
                    key={gpu.index}
                    onClick={() => gpu.is_supported && setSelectedGpu(gpu.index)}
                    className={`card cursor-pointer text-left ${
                      selectedGpu === gpu.index ? "border-alice-500" : ""
                    } ${!gpu.is_supported ? "opacity-50" : ""}`}
                  >
                    <div className="flex items-center gap-3 mb-2">
                      <div
                        className={`w-3 h-3 rounded-full ${
                          gpu.is_supported ? "bg-green-500" : "bg-red-500"
                        }`}
                      />
                      <span className="font-semibold">{gpu.name}</span>
                    </div>
                    <div className="text-sm text-zinc-400">
                      {gpu.vram_total_gb.toFixed(1)} GB VRAM
                      {gpu.cuda_version && ` • CUDA ${gpu.cuda_version}`}
                    </div>
                    <div
                      className={`text-sm mt-2 ${
                        gpu.is_supported ? "text-green-500" : "text-red-500"
                      }`}
                    >
                      {gpu.support_reason}
                    </div>
                  </div>
                ))}
                <div className="flex gap-3 pt-4">
                  <button onClick={() => setStep("network")} className="btn btn-secondary flex-1">
                    Back
                  </button>
                  <button
                    onClick={() => setStep("model")}
                    disabled={!gpus.some((g) => g.is_supported)}
                    className="btn btn-primary flex-1 disabled:opacity-50"
                  >
                    Continue
                  </button>
                </div>
              </div>
            )}
          </div>
        );

      case "model":
        return (
          <div className="text-center">
            <h2 className="text-2xl font-bold mb-6">Download Model</h2>
            <div className="max-w-md mx-auto">
              {downloadProgress === 0 && !loading ? (
                <div className="space-y-4">
                  <p className="text-zinc-400">
                    Download the AI model (~7 GB). This may take a few minutes depending on your
                    connection speed.
                  </p>
                  <button onClick={downloadModel} className="btn btn-primary w-full">
                    Download Model
                  </button>
                  <button onClick={() => setStep("gpu")} className="btn btn-secondary w-full">
                    Back
                  </button>
                </div>
              ) : (
                <div className="space-y-4">
                  <div className="progress-bar h-3">
                    <div
                      className="progress-fill"
                      style={{ width: `${downloadProgress}%` }}
                    />
                  </div>
                  <div className="text-zinc-400">{downloadStatus}</div>
                  <div className="font-mono text-alice-500 text-xl">
                    {downloadProgress.toFixed(1)}%
                  </div>
                </div>
              )}
              {error && <div className="text-red-500 mt-4">{error}</div>}
            </div>
          </div>
        );

      case "wallet":
        return (
          <div className="text-center">
            <h2 className="text-2xl font-bold mb-6">Setup Wallet</h2>
            <div className="max-w-md mx-auto">
              {showMnemonic ? (
                <div className="space-y-4">
                  <div className="card text-left">
                    <div className="text-sm text-zinc-400 mb-2">Your wallet address:</div>
                    <div className="font-mono text-sm text-alice-500 break-all">
                      {walletAddress}
                    </div>
                  </div>
                  <div className="card border-yellow-500/50 text-left">
                    <div className="text-yellow-500 text-sm mb-2">
                      ⚠ Save these words securely. You won't see them again!
                    </div>
                    <div className="grid grid-cols-3 gap-2 mt-3">
                      {mnemonic.split(" ").map((word, i) => (
                        <div key={i} className="bg-zinc-800 rounded px-2 py-1 text-sm">
                          <span className="text-zinc-500">{i + 1}.</span> {word}
                        </div>
                      ))}
                    </div>
                  </div>
                  <button
                    onClick={() => saveAndFinish(walletAddress)}
                    className="btn btn-primary w-full"
                  >
                    I've saved my recovery phrase
                  </button>
                </div>
              ) : importMode ? (
                <div className="space-y-4">
                  <textarea
                    value={importMnemonic}
                    onChange={(e) => setImportMnemonic(e.target.value)}
                    placeholder="Enter your 12-word recovery phrase..."
                    className="w-full h-24 bg-zinc-900 border border-zinc-700 rounded-lg p-3 text-sm resize-none focus:border-alice-500 outline-none"
                  />
                  {error && <div className="text-red-500 text-sm">{error}</div>}
                  <button
                    onClick={importWallet}
                    disabled={loading || importMnemonic.trim().split(/\s+/).length !== 12}
                    className="btn btn-primary w-full disabled:opacity-50"
                  >
                    {loading ? "Importing..." : "Import Wallet"}
                  </button>
                  <button
                    onClick={() => {
                      setImportMode(false);
                      setError(null);
                    }}
                    className="btn btn-secondary w-full"
                  >
                    Back
                  </button>
                </div>
              ) : (
                <div className="space-y-4">
                  <p className="text-zinc-400">
                    Create a new wallet or import an existing one to receive ALICE rewards.
                  </p>
                  <button
                    onClick={createWallet}
                    disabled={loading}
                    className="btn btn-primary w-full"
                  >
                    {loading ? "Creating..." : "Create New Wallet"}
                  </button>
                  <button
                    onClick={() => setImportMode(true)}
                    className="btn btn-secondary w-full"
                  >
                    Import Existing Wallet
                  </button>
                  <button onClick={() => setStep("model")} className="btn btn-secondary w-full">
                    Back
                  </button>
                </div>
              )}
            </div>
          </div>
        );

      case "role":
        const roles = [
          {
            id: "trainer",
            label: "Trainer",
            desc: "Train the model by computing gradients",
            req: "GPU with 24GB+ VRAM",
            reward: "94%",
            stake: "No stake required",
          },
          {
            id: "scorer",
            label: "Scorer",
            desc: "Validate gradient quality and earn rewards",
            req: "CPU with 24GB+ RAM",
            reward: "5%",
            stake: "5,000 ALICE stake",
          },
          {
            id: "aggregator",
            label: "Aggregator",
            desc: "Aggregate gradients from miners",
            req: "CPU with 64GB+ RAM, 1TB SSD",
            reward: "1%",
            stake: "20,000 ALICE stake",
          },
        ];
        return (
          <div>
            <h2 className="text-2xl font-bold mb-2 text-center">Select Your Role</h2>
            <p className="text-zinc-500 text-sm text-center mb-6">
              Choose how you want to contribute to the network
            </p>
            <div className="space-y-3 max-w-md mx-auto">
              {roles.map((r) => (
                <div
                  key={r.id}
                  onClick={() => setSelectedRole(r.id)}
                  className={`card cursor-pointer transition-colors ${
                    selectedRole === r.id ? "border-alice-500" : "hover:border-zinc-600"
                  }`}
                >
                  <div className="flex items-start gap-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-semibold">{r.label}</span>
                        <span className="text-xs text-alice-500 bg-alice-500/10 px-2 py-0.5 rounded">
                          {r.reward} rewards
                        </span>
                        <span className="text-xs text-zinc-500 bg-zinc-800 px-2 py-0.5 rounded">
                          {r.stake}
                        </span>
                      </div>
                      <div className="text-sm text-zinc-400 mb-1">{r.desc}</div>
                      <div className="text-xs text-zinc-600">Requires: {r.req}</div>
                    </div>
                    <div
                      className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 mt-0.5 ${
                        selectedRole === r.id ? "border-alice-500" : "border-zinc-700"
                      }`}
                    >
                      {selectedRole === r.id && (
                        <div className="w-2.5 h-2.5 rounded-full bg-alice-500" />
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>
            {error && <div className="text-red-500 text-sm text-center mt-4">{error}</div>}
            <div className="text-center mt-6">
              <button
                onClick={async () => {
                  if (!selectedRole) {
                    setError("Please select a role");
                    return;
                  }
                  setLoading(true);
                  try {
                    await invoke("save_role", { role: selectedRole });
                    setStep("ready");
                  } catch (e: any) {
                    setError(e.toString());
                  } finally {
                    setLoading(false);
                  }
                }}
                disabled={!selectedRole || loading}
                className="btn btn-primary px-8 py-3 disabled:opacity-50"
              >
                {loading ? "Saving..." : "Continue"}
              </button>
            </div>
          </div>
        );

      case "ready":
        const actionLabel =
          selectedRole === "scorer"
            ? "Start Scoring"
            : selectedRole === "aggregator"
            ? "Start Aggregating"
            : "Start Mining";
        return (
          <div className="text-center">
            <div className="w-20 h-20 mx-auto mb-6 rounded-full bg-green-500/20 flex items-center justify-center">
              <svg className="w-10 h-10 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3}>
                <path d="M20 6L9 17l-5-5" />
              </svg>
            </div>
            <h2 className="text-2xl font-bold mb-3">You're all set!</h2>
            <p className="text-zinc-400 mb-8">
              Your node is ready. Click below to begin earning ALICE.
            </p>
            <button
              onClick={() => onComplete(walletAddress, selectedRole || "trainer")}
              className="btn btn-primary text-lg px-8 py-3"
            >
              {actionLabel}
            </button>
          </div>
        );
    }
  };

  return (
    <div className="h-screen bg-black flex items-center justify-center p-8">
      <div className="max-w-xl w-full">{renderStep()}</div>
    </div>
  );
}
