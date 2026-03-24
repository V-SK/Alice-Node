use serde::{Deserialize, Serialize};
use std::io::BufRead;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::{Manager, State};

use super::setup;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum AggregatingStatus {
    Idle,
    Starting,
    Running,
    Stopping,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatingState {
    pub status: AggregatingStatus,
    pub wallet_address: Option<String>,
    pub connected_miners: u32,
    pub max_miners: u32,
    pub gradients_received: u64,
    pub epoch_gradients: u64,
    pub bandwidth_mbps: f64,
    pub model_version: Option<u64>,
    pub error_message: Option<String>,
}

pub struct AggregatingProcess {
    pub child: Option<Child>,
    pub state: AggregatingState,
}

impl Default for AggregatingProcess {
    fn default() -> Self {
        Self {
            child: None,
            state: AggregatingState {
                status: AggregatingStatus::Idle,
                wallet_address: None,
                connected_miners: 0,
                max_miners: 200,
                gradients_received: 0,
                epoch_gradients: 0,
                bandwidth_mbps: 0.0,
                model_version: None,
                error_message: None,
            },
        }
    }
}

pub type AggregatingProcessState = Mutex<AggregatingProcess>;

fn get_aggregator_command() -> (String, Vec<String>) {
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
        return (binary_path.to_string_lossy().to_string(), vec!["aggregate".to_string()]);
    }

    // Use venv Python with alice-node code directory
    if let (Ok(venv_dir), Ok(code_dir)) = (setup::get_venv_dir(), setup::get_code_dir()) {
        let python = setup::venv_python(&venv_dir);
        let script = code_dir.join("alice_node.py");
        if python.exists() && script.exists() {
            return (
                python.to_string_lossy().to_string(),
                vec![script.to_string_lossy().to_string(), "aggregate".to_string()],
            );
        }
    }

    // Last resort fallback: system Python
    #[cfg(target_os = "windows")]
    let python = "python";
    #[cfg(not(target_os = "windows"))]
    let python = "python3";

    (python.to_string(), vec!["alice_node.py".to_string(), "aggregate".to_string()])
}

#[tauri::command]
pub fn start_aggregating(
    wallet_address: String,
    state: State<'_, AggregatingProcessState>,
    app_handle: tauri::AppHandle,
) -> Result<(), String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if process.state.status == AggregatingStatus::Running {
        return Err("Aggregating is already running".to_string());
    }

    process.state.status = AggregatingStatus::Starting;
    process.state.wallet_address = Some(wallet_address.clone());

    let ps_url = super::settings::load_ps_url();
    let (program, mut args) = get_aggregator_command();
    args.extend(["--address".to_string(), wallet_address.clone()]);
    args.extend(["--ps-url".to_string(), ps_url]);

    let mut cmd = Command::new(&program);
    for arg in &args {
        cmd.arg(arg);
    }
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());

    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(stdout) = child.stdout.take() {
                let handle = app_handle.clone();
                std::thread::spawn(move || {
                    let reader = std::io::BufReader::new(stdout);
                    for line in reader.lines() {
                        if let Ok(line) = line {
                            let _ = handle.emit_all(
                                "aggregator-log",
                                serde_json::json!({ "type": "stdout", "message": line }),
                            );
                        }
                    }
                });
            }

            if let Some(stderr) = child.stderr.take() {
                let handle = app_handle.clone();
                std::thread::spawn(move || {
                    let reader = std::io::BufReader::new(stderr);
                    for line in reader.lines() {
                        if let Ok(line) = line {
                            let _ = handle.emit_all(
                                "aggregator-log",
                                serde_json::json!({ "type": "stderr", "message": line }),
                            );
                        }
                    }
                });
            }

            process.child = Some(child);
            process.state.status = AggregatingStatus::Running;
            log::info!("Aggregating started for address {}", wallet_address);
            Ok(())
        }
        Err(e) => {
            process.state.status = AggregatingStatus::Error;
            process.state.error_message = Some(e.to_string());
            Err(format!("Failed to start aggregator: {}", e))
        }
    }
}

#[tauri::command]
pub fn stop_aggregating(state: State<'_, AggregatingProcessState>) -> Result<(), String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if process.state.status != AggregatingStatus::Running {
        return Ok(());
    }

    process.state.status = AggregatingStatus::Stopping;

    if let Some(ref mut child) = process.child {
        graceful_kill_aggregator(child);
    }

    process.child = None;
    process.state.status = AggregatingStatus::Idle;
    log::info!("Aggregating stopped");
    Ok(())
}

/// Cross-platform graceful process termination for aggregator.
fn graceful_kill_aggregator(child: &mut Child) {
    let pid = child.id();

    #[cfg(unix)]
    {
        unsafe {
            libc::kill(pid as i32, libc::SIGTERM);
        }
        for _ in 0..10 {
            std::thread::sleep(std::time::Duration::from_millis(500));
            if let Ok(Some(_)) = child.try_wait() {
                return;
            }
        }
    }

    #[cfg(windows)]
    {
        let _ = Command::new("taskkill")
            .args(["/PID", &pid.to_string()])
            .output();
        for _ in 0..10 {
            std::thread::sleep(std::time::Duration::from_millis(500));
            if let Ok(Some(_)) = child.try_wait() {
                return;
            }
        }
        log::warn!("Aggregator process {} did not exit gracefully, force killing", pid);
        let _ = Command::new("taskkill")
            .args(["/F", "/PID", &pid.to_string()])
            .output();
    }

    match child.try_wait() {
        Ok(Some(_)) => {}
        _ => {
            let _ = child.kill();
        }
    }
    let _ = child.wait();
}

#[tauri::command]
pub fn get_aggregating_status(
    state: State<'_, AggregatingProcessState>,
) -> Result<AggregatingState, String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if let Some(ref mut child) = process.child {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() {
                    process.state.status = AggregatingStatus::Error;
                    process.state.error_message =
                        Some(format!("Aggregator process exited with status: {}", status));
                } else {
                    process.state.status = AggregatingStatus::Idle;
                }
                process.child = None;
            }
            Ok(None) => {
                process.state.status = AggregatingStatus::Running;
            }
            Err(e) => {
                process.state.status = AggregatingStatus::Error;
                process.state.error_message = Some(e.to_string());
            }
        }
    }

    Ok(process.state.clone())
}
