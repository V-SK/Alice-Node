use serde::{Deserialize, Serialize};
use std::io::BufRead;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::{Manager, State};

use super::setup;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum ScoringStatus {
    Idle,
    Starting,
    Running,
    Stopping,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoringState {
    pub status: ScoringStatus,
    pub wallet_address: Option<String>,
    pub evaluations: u64,
    pub epoch_evals: u64,
    pub queue_depth: u32,
    pub strikes: u32,
    pub avg_time_secs: f64,
    pub model_version: Option<u64>,
    pub error_message: Option<String>,
}

pub struct ScoringProcess {
    pub child: Option<Child>,
    pub state: ScoringState,
}

impl Default for ScoringProcess {
    fn default() -> Self {
        Self {
            child: None,
            state: ScoringState {
                status: ScoringStatus::Idle,
                wallet_address: None,
                evaluations: 0,
                epoch_evals: 0,
                queue_depth: 0,
                strikes: 0,
                avg_time_secs: 0.0,
                model_version: None,
                error_message: None,
            },
        }
    }
}

pub type ScoringProcessState = Mutex<ScoringProcess>;

fn get_scorer_command() -> (String, Vec<String>) {
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
        return (binary_path.to_string_lossy().to_string(), vec!["score".to_string()]);
    }

    // Use venv Python with alice-node code directory
    if let (Ok(venv_dir), Ok(code_dir)) = (setup::get_venv_dir(), setup::get_code_dir()) {
        let python = setup::venv_python(&venv_dir);
        let script = code_dir.join("alice_node.py");
        if python.exists() && script.exists() {
            return (
                python.to_string_lossy().to_string(),
                vec![script.to_string_lossy().to_string(), "score".to_string()],
            );
        }
    }

    // Last resort fallback: system Python
    #[cfg(target_os = "windows")]
    let python = "python";
    #[cfg(not(target_os = "windows"))]
    let python = "python3";

    (python.to_string(), vec!["alice_node.py".to_string(), "score".to_string()])
}

#[tauri::command]
pub fn start_scoring(
    wallet_address: String,
    state: State<'_, ScoringProcessState>,
    app_handle: tauri::AppHandle,
) -> Result<(), String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if process.state.status == ScoringStatus::Running {
        return Err("Scoring is already running".to_string());
    }

    process.state.status = ScoringStatus::Starting;
    process.state.wallet_address = Some(wallet_address.clone());

    let (program, mut args) = get_scorer_command();
    args.extend(["--address".to_string(), wallet_address.clone()]);
    args.extend(["--ps-url".to_string(), "https://ps.aliceprotocol.org".to_string()]);

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
                                "scorer-log",
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
                                "scorer-log",
                                serde_json::json!({ "type": "stderr", "message": line }),
                            );
                        }
                    }
                });
            }

            process.child = Some(child);
            process.state.status = ScoringStatus::Running;
            log::info!("Scoring started for address {}", wallet_address);
            Ok(())
        }
        Err(e) => {
            process.state.status = ScoringStatus::Error;
            process.state.error_message = Some(e.to_string());
            Err(format!("Failed to start scorer: {}", e))
        }
    }
}

#[tauri::command]
pub fn stop_scoring(state: State<'_, ScoringProcessState>) -> Result<(), String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if process.state.status != ScoringStatus::Running {
        return Ok(());
    }

    process.state.status = ScoringStatus::Stopping;

    if let Some(ref mut child) = process.child {
        #[cfg(unix)]
        {
            unsafe {
                libc::kill(child.id() as i32, libc::SIGTERM);
            }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }

        match child.try_wait() {
            Ok(Some(_)) => {}
            _ => {
                let _ = child.kill();
            }
        }

        let _ = child.wait();
    }

    process.child = None;
    process.state.status = ScoringStatus::Idle;
    log::info!("Scoring stopped");
    Ok(())
}

#[tauri::command]
pub fn get_scoring_status(state: State<'_, ScoringProcessState>) -> Result<ScoringState, String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if let Some(ref mut child) = process.child {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() {
                    process.state.status = ScoringStatus::Error;
                    process.state.error_message =
                        Some(format!("Scorer process exited with status: {}", status));
                } else {
                    process.state.status = ScoringStatus::Idle;
                }
                process.child = None;
            }
            Ok(None) => {
                process.state.status = ScoringStatus::Running;
            }
            Err(e) => {
                process.state.status = ScoringStatus::Error;
                process.state.error_message = Some(e.to_string());
            }
        }
    }

    Ok(process.state.clone())
}
