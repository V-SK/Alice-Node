use serde::{Deserialize, Serialize};
use std::io::BufRead;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::{Manager, State};

use super::setup;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum MiningStatus {
    Idle,
    Starting,
    Running,
    Stopping,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MiningState {
    pub status: MiningStatus,
    pub wallet_address: Option<String>,
    pub gpu_index: u32,
    pub current_epoch: Option<u64>,
    pub current_shard: Option<u64>,
    pub current_loss: Option<f64>,
    pub shards_completed: u64,
    pub error_message: Option<String>,
}

pub struct MiningProcess {
    pub child: Option<Child>,
    pub state: MiningState,
}

impl Default for MiningProcess {
    fn default() -> Self {
        Self {
            child: None,
            state: MiningState {
                status: MiningStatus::Idle,
                wallet_address: None,
                gpu_index: 0,
                current_epoch: None,
                current_shard: None,
                current_loss: None,
                shards_completed: 0,
                error_message: None,
            },
        }
    }
}

pub type MiningProcessState = Mutex<MiningProcess>;

/// Try to find the bundled miner binary; fall back to venv Python.
fn get_miner_command() -> (String, Vec<String>) {
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_default();

    #[cfg(target_os = "windows")]
    let binary_name = "alice-miner-core.exe";
    #[cfg(not(target_os = "windows"))]
    let binary_name = "alice-miner-core";

    let binary_path = exe_dir.join(binary_name);
    if binary_path.exists() {
        return (binary_path.to_string_lossy().to_string(), vec![]);
    }

    // Use venv Python with alice-node code directory
    if let (Ok(venv_dir), Ok(code_dir)) = (setup::get_venv_dir(), setup::get_code_dir()) {
        let python = setup::venv_python(&venv_dir);
        let script = code_dir.join("alice_node.py");
        if python.exists() && script.exists() {
            return (
                python.to_string_lossy().to_string(),
                vec![script.to_string_lossy().to_string()],
            );
        }
    }

    // Last resort fallback: system Python
    #[cfg(target_os = "windows")]
    let python = "python";
    #[cfg(not(target_os = "windows"))]
    let python = "python3";

    (python.to_string(), vec!["alice_node.py".to_string()])
}

#[tauri::command]
pub fn start_mining(
    wallet_address: String,
    gpu_index: u32,
    device: Option<String>,
    state: State<'_, MiningProcessState>,
    app_handle: tauri::AppHandle,
) -> Result<(), String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if process.state.status == MiningStatus::Running {
        return Err("Mining is already running".to_string());
    }

    process.state.status = MiningStatus::Starting;
    process.state.wallet_address = Some(wallet_address.clone());
    process.state.gpu_index = gpu_index;

    // Determine device: use frontend-provided value, or infer from gpu_index
    let device_str = device.unwrap_or_else(|| {
        if gpu_index == 999 {
            "cpu".to_string()
        } else if cfg!(target_os = "macos") {
            "mps".to_string()
        } else {
            "cuda".to_string()
        }
    });

    // #14: Read PS URL from settings, fall back to default
    let ps_url = super::settings::load_ps_url();

    let (program, prefix_args) = get_miner_command();
    let mut cmd = Command::new(&program);
    for arg in &prefix_args {
        cmd.arg(arg);
    }
    cmd.arg("mine")
        .arg("--ps-url")
        .arg(&ps_url)
        .arg("--address")
        .arg(&wallet_address)
        .arg("--device")
        .arg(&device_str)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    match cmd.spawn() {
        Ok(mut child) => {
            // Forward stdout to frontend via Tauri events
            if let Some(stdout) = child.stdout.take() {
                let handle = app_handle.clone();
                std::thread::spawn(move || {
                    let reader = std::io::BufReader::new(stdout);
                    for line in reader.lines() {
                        if let Ok(line) = line {
                            let _ = handle.emit_all("miner-log", serde_json::json!({
                                "type": "stdout",
                                "message": line
                            }));
                        }
                    }
                });
            }

            // Forward stderr to frontend via Tauri events
            if let Some(stderr) = child.stderr.take() {
                let handle = app_handle.clone();
                std::thread::spawn(move || {
                    let reader = std::io::BufReader::new(stderr);
                    for line in reader.lines() {
                        if let Ok(line) = line {
                            let _ = handle.emit_all("miner-log", serde_json::json!({
                                "type": "stderr",
                                "message": line
                            }));
                        }
                    }
                });
            }

            process.child = Some(child);
            process.state.status = MiningStatus::Running;
            log::info!("Mining started for address {} on device {} (gpu_index={})", wallet_address, device_str, gpu_index);

            // #15: Auto-restart on crash (max 5 restarts, 10s interval)
            let restart_handle = app_handle.clone();
            let restart_wallet = wallet_address.clone();
            let restart_device = device_str.clone();
            let restart_ps_url = ps_url.clone();
            std::thread::spawn(move || {
                auto_restart_miner(
                    restart_handle,
                    restart_wallet,
                    restart_device,
                    restart_ps_url,
                );
            });

            Ok(())
        }
        Err(e) => {
            process.state.status = MiningStatus::Error;
            process.state.error_message = Some(e.to_string());
            Err(format!("Failed to start miner: {}", e))
        }
    }
}

/// #15: Monitor miner process and auto-restart on crash (max 5 times, 10s interval)
fn auto_restart_miner(
    app_handle: tauri::AppHandle,
    wallet_address: String,
    device_str: String,
    ps_url: String,
) {
    let max_restarts: u32 = 5;
    let restart_delay = std::time::Duration::from_secs(10);

    // Macro to lock managed state — avoids closure lifetime issues (E0515)
    macro_rules! lock_state {
        () => {
            app_handle.state::<MiningProcessState>().inner().lock().map_err(|_| ())
        };
    }

    // Wait for the initial process to finish
    loop {
        std::thread::sleep(std::time::Duration::from_secs(2));

        let mut process = match lock_state!() {
            Ok(p) => p,
            Err(_) => return,
        };

        // If user manually stopped, don't restart
        if process.state.status == MiningStatus::Idle
            || process.state.status == MiningStatus::Stopping
        {
            return;
        }

        // Check if child exited
        let exited = if let Some(ref mut child) = process.child {
            matches!(child.try_wait(), Ok(Some(_)))
        } else {
            return;
        };

        if !exited {
            continue;
        }

        // Process crashed — attempt restarts
        process.child = None;
        drop(process);

        let mut restart_count: u32 = 0;
        loop {
            restart_count += 1;
            if restart_count > max_restarts {
                log::error!("Miner crashed {} times, giving up", max_restarts);
                let _ = app_handle.emit_all("miner-error", serde_json::json!({
                    "message": format!("Miner crashed {} times. Auto-restart stopped.", max_restarts)
                }));
                if let Ok(mut p) = lock_state!() {
                    p.state.status = MiningStatus::Error;
                    p.state.error_message = Some(format!(
                        "Miner crashed {} times. Please check logs and restart manually.",
                        max_restarts
                    ));
                }
                return;
            }

            log::warn!(
                "Miner crashed, attempting restart {}/{} in {}s",
                restart_count,
                max_restarts,
                restart_delay.as_secs()
            );
            let _ = app_handle.emit_all("miner-log", serde_json::json!({
                "type": "stderr",
                "message": format!("Miner crashed. Restarting ({}/{})...", restart_count, max_restarts)
            }));

            std::thread::sleep(restart_delay);

            // Check if user stopped mining while we were waiting
            if let Ok(p) = lock_state!() {
                if p.state.status == MiningStatus::Idle || p.state.status == MiningStatus::Stopping {
                    return;
                }
            }

            // Try to restart
            let (program, prefix_args) = get_miner_command();
            let mut cmd = Command::new(&program);
            for arg in &prefix_args {
                cmd.arg(arg);
            }
            cmd.arg("--ps-url")
                .arg(&ps_url)
                .arg("--address")
                .arg(&wallet_address)
                .arg("--device")
                .arg(&device_str)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());

            match cmd.spawn() {
                Ok(mut child) => {
                    if let Some(stdout) = child.stdout.take() {
                        let handle = app_handle.clone();
                        std::thread::spawn(move || {
                            let reader = std::io::BufReader::new(stdout);
                            for line in reader.lines() {
                                if let Ok(line) = line {
                                    let _ = handle.emit_all("miner-log", serde_json::json!({
                                        "type": "stdout",
                                        "message": line
                                    }));
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
                                    let _ = handle.emit_all("miner-log", serde_json::json!({
                                        "type": "stderr",
                                        "message": line
                                    }));
                                }
                            }
                        });
                    }

                    if let Ok(mut p) = lock_state!() {
                        p.child = Some(child);
                        p.state.status = MiningStatus::Running;
                    }

                    log::info!("Miner restarted (attempt {}/{})", restart_count, max_restarts);

                    // Wait for this instance to exit
                    loop {
                        std::thread::sleep(std::time::Duration::from_secs(2));
                        let mut process = match lock_state!() {
                            Ok(p) => p,
                            Err(_) => return,
                        };
                        if process.state.status == MiningStatus::Idle
                            || process.state.status == MiningStatus::Stopping
                        {
                            return;
                        }
                        let exited = if let Some(ref mut child) = process.child {
                            matches!(child.try_wait(), Ok(Some(_)))
                        } else {
                            return;
                        };
                        if exited {
                            process.child = None;
                            break;
                        }
                    }
                    // Loop back to try another restart
                }
                Err(e) => {
                    log::error!("Failed to restart miner: {}", e);
                    // Count this as a failed restart attempt and continue loop
                }
            }
        }
    }
}

#[tauri::command]
pub fn stop_mining(state: State<'_, MiningProcessState>) -> Result<(), String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    if process.state.status != MiningStatus::Running {
        return Ok(()); // Already stopped
    }

    process.state.status = MiningStatus::Stopping;

    if let Some(ref mut child) = process.child {
        graceful_kill(child);
    }

    process.child = None;
    process.state.status = MiningStatus::Idle;
    process.state.current_epoch = None;
    process.state.current_shard = None;
    process.state.current_loss = None;

    log::info!("Mining stopped");
    Ok(())
}

/// Cross-platform graceful process termination.
/// Unix: SIGTERM → wait 5s → SIGKILL
/// Windows: taskkill (graceful) → wait 5s → taskkill /F (force)
fn graceful_kill(child: &mut Child) {
    let pid = child.id();

    #[cfg(unix)]
    {
        // Send SIGTERM
        unsafe {
            libc::kill(pid as i32, libc::SIGTERM);
        }
        // Wait up to 5 seconds for graceful shutdown
        for _ in 0..10 {
            std::thread::sleep(std::time::Duration::from_millis(500));
            if let Ok(Some(_)) = child.try_wait() {
                return;
            }
        }
    }

    #[cfg(windows)]
    {
        // Try graceful shutdown first (taskkill without /F)
        let _ = Command::new("taskkill")
            .args(["/PID", &pid.to_string()])
            .output();

        // Wait up to 5 seconds for graceful shutdown
        for _ in 0..10 {
            std::thread::sleep(std::time::Duration::from_millis(500));
            if let Ok(Some(_)) = child.try_wait() {
                return;
            }
        }

        // Force kill with /F
        log::warn!("Process {} did not exit gracefully, force killing", pid);
        let _ = Command::new("taskkill")
            .args(["/F", "/PID", &pid.to_string()])
            .output();
    }

    // Force kill if still running (fallback for Unix)
    match child.try_wait() {
        Ok(Some(_)) => {}
        _ => {
            let _ = child.kill();
        }
    }
    let _ = child.wait();
}

#[tauri::command]
pub fn get_mining_status(state: State<'_, MiningProcessState>) -> Result<MiningState, String> {
    let mut process = state.lock().map_err(|e| e.to_string())?;

    // Check if child process is still running
    if let Some(ref mut child) = process.child {
        match child.try_wait() {
            Ok(Some(status)) => {
                // Process exited
                if !status.success() {
                    process.state.status = MiningStatus::Error;
                    process.state.error_message =
                        Some(format!("Miner process exited with status: {}", status));
                } else {
                    process.state.status = MiningStatus::Idle;
                }
                process.child = None;
            }
            Ok(None) => {
                // Still running
                process.state.status = MiningStatus::Running;
            }
            Err(e) => {
                process.state.status = MiningStatus::Error;
                process.state.error_message = Some(e.to_string());
            }
        }
    }

    Ok(process.state.clone())
}
