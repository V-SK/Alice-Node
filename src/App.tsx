import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/tauri";
import Sidebar from "./components/Sidebar";
import Dashboard from "./pages/Dashboard";
import ScorerDashboard from "./pages/ScorerDashboard";
import AggregatorDashboard from "./pages/AggregatorDashboard";
import Wallet from "./pages/Wallet";
import Hardware from "./pages/Hardware";
import Staking from "./pages/Staking";
import Earnings from "./pages/Earnings";
import Logs from "./pages/Logs";
import Settings from "./pages/Settings";
import Setup from "./pages/Setup";
import { useAppStore } from "./hooks/useAppStore";

type Page = "dashboard" | "wallet" | "hardware" | "staking" | "earnings" | "logs" | "settings";

function App() {
  const [currentPage, setCurrentPage] = useState<Page>("dashboard");
  const [isSetupComplete, setIsSetupComplete] = useState<boolean | null>(null);
  const { setWalletAddress, setNetworkStatus, setGpuInfo, role, setRole } = useAppStore();

  useEffect(() => {
    const checkSetup = async () => {
      try {
        const address = await invoke<string | null>("get_wallet_address");
        const savedRole = await invoke<string | null>("get_role");
        if (address && savedRole) {
          setWalletAddress(address);
          setRole(savedRole as any);
          setIsSetupComplete(true);
        } else {
          setIsSetupComplete(false);
        }
      } catch (e) {
        console.error("Failed to check setup:", e);
        setIsSetupComplete(false);
      }
    };

    const checkNetwork = async () => {
      try {
        const status = await invoke<any>("diagnose_network");
        setNetworkStatus(status);
      } catch (e) {
        console.error("Network check failed:", e);
      }
    };

    const checkGpu = async () => {
      try {
        const gpus = await invoke<any[]>("detect_gpu");
        setGpuInfo(gpus);
      } catch (e) {
        console.error("GPU check failed:", e);
      }
    };

    checkSetup();
    checkNetwork();
    checkGpu();
  }, []);

  const handleSetupComplete = (address: string, selectedRole: string) => {
    setWalletAddress(address);
    setRole(selectedRole as any);
    setIsSetupComplete(true);
  };

  if (isSetupComplete === null) {
    return (
      <div className="h-screen bg-black flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 mx-auto mb-4 border-4 border-alice-500 border-t-transparent rounded-full animate-spin" />
          <p className="text-zinc-400">Loading...</p>
        </div>
      </div>
    );
  }

  if (!isSetupComplete) {
    return <Setup onComplete={handleSetupComplete} />;
  }

  const renderPage = () => {
    switch (currentPage) {
      case "dashboard":
        if (role === "scorer") return <ScorerDashboard />;
        if (role === "aggregator") return <AggregatorDashboard />;
        return <Dashboard />;
      case "wallet":
        return <Wallet />;
      case "hardware":
        return <Hardware />;
      case "staking":
        return <Staking />;
      case "earnings":
        return <Earnings />;
      case "logs":
        return <Logs />;
      case "settings":
        return <Settings onSwitchRole={() => setIsSetupComplete(false)} />;
      default:
        return <Dashboard />;
    }
  };

  return (
    <div className="h-screen bg-black flex overflow-hidden">
      <Sidebar currentPage={currentPage} onPageChange={setCurrentPage} />
      <main className="flex-1 overflow-auto">{renderPage()}</main>
    </div>
  );
}

export default App;
