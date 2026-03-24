import { useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import { useAppStore } from "../hooks/useAppStore";

export default function Logs() {
  const { logs, clearLogs, addLog } = useAppStore();

  // Subscribe to all role log events from the Rust backend
  useEffect(() => {
    const unlisteners = [
      listen<{ type: string; message: string }>("miner-log", (e) => {
        const logType = e.payload.type === "stderr" ? "error" : "miner";
        addLog(e.payload.message, logType);
      }),
      listen<{ type: string; message: string }>("scorer-log", (e) => {
        const logType = e.payload.type === "stderr" ? "error" : "scorer";
        addLog(e.payload.message, logType);
      }),
      listen<{ type: string; message: string }>("aggregator-log", (e) => {
        const logType = e.payload.type === "stderr" ? "error" : "aggregator";
        addLog(e.payload.message, logType);
      }),
      listen("setup-progress", (e) => {
        addLog(JSON.stringify(e.payload), "system");
      }),
    ];
    return () => {
      unlisteners.forEach((p) => p.then((f) => f()));
    };
  }, [addLog]);

  const copyLogs = () => {
    const text = logs.map((l) => `[${l.time}] ${l.msg}`).join("\n");
    navigator.clipboard.writeText(text);
  };

  const exportLogs = () => {
    const text = logs.map((l) => `[${l.time}] ${l.msg}`).join("\n");
    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `alice-miner-logs-${new Date().toISOString().split("T")[0]}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Logs</h1>
        <div className="flex gap-2">
          <button onClick={copyLogs} className="btn btn-secondary text-sm">
            Copy All
          </button>
          <button onClick={exportLogs} className="btn btn-secondary text-sm">
            Export
          </button>
          <button onClick={clearLogs} className="btn btn-secondary text-sm">
            Clear
          </button>
        </div>
      </div>

      <div className="log-console">
        {logs.length === 0 ? (
          <div className="text-zinc-500 text-center py-8">No logs yet</div>
        ) : (
          logs.map((log, i) => (
            <div key={i} className="log-line">
              <span className="log-time">{log.time}</span>
              <span className={`log-msg ${log.type}`}>{log.msg}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
