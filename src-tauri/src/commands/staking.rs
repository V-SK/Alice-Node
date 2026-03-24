use serde::{Deserialize, Serialize};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StakingInfo {
    pub staked: u64,
    pub status: String, // "None", "Pending", "Active"
    pub role: Option<String>,
}

fn get_alice_node_bin() -> String {
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_default();

    #[cfg(target_os = "windows")]
    let binary_name = "alice-node.exe";
    #[cfg(not(target_os = "windows"))]
    let binary_name = "alice-node";

    let binary_path = exe_dir.join(binary_name);
    if binary_path.exists() {
        return binary_path.to_string_lossy().to_string();
    }

    // Fallback: assume alice-node is on PATH
    binary_name.to_string()
}

#[tauri::command]
pub fn stake(amount: u64) -> Result<String, String> {
    let bin = get_alice_node_bin();

    let output = Command::new(&bin)
        .arg("stake")
        .arg("--amount")
        .arg(amount.to_string())
        .output()
        .map_err(|e| format!("Failed to run alice-node: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

#[tauri::command]
pub fn unstake() -> Result<String, String> {
    let bin = get_alice_node_bin();

    let output = Command::new(&bin)
        .arg("unstake")
        .output()
        .map_err(|e| format!("Failed to run alice-node: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

#[tauri::command]
pub fn get_staking_info() -> Result<StakingInfo, String> {
    let bin = get_alice_node_bin();

    let output = Command::new(&bin)
        .arg("status")
        .arg("--json")
        .output();

    match output {
        Ok(out) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            // Try to parse JSON; fall back to default if CLI not available yet
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&text) {
                let staked = val["staked"].as_u64().unwrap_or(0);
                let status = val["staking_status"]
                    .as_str()
                    .unwrap_or("None")
                    .to_string();
                let role = val["role"].as_str().map(|s| s.to_string());
                return Ok(StakingInfo { staked, status, role });
            }
            Ok(StakingInfo {
                staked: 0,
                status: "None".to_string(),
                role: None,
            })
        }
        _ => {
            // CLI not available; return empty state so UI still renders
            Ok(StakingInfo {
                staked: 0,
                status: "None".to_string(),
                role: None,
            })
        }
    }
}
