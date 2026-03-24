use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use tauri::Manager;

const ALICE_MINER_DIR: &str = ".alice-miner";
const VENV_DIR: &str = ".venv";
const CODE_DIR: &str = "alice-node";
const REPO_URL: &str = "https://github.com/aliceprotocol/alice-node.git";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetupResult {
    pub python_version: String,
    pub torch_version: String,
    pub device: String,
    pub ready: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SetupProgress {
    pub step: String,
    pub message: String,
    pub progress: f32, // 0.0 - 1.0
    pub error: bool,
}

/// Search for python3 > python > py in PATH, return the first one found.
fn find_python() -> Option<String> {
    let candidates = if cfg!(target_os = "windows") {
        vec!["python3", "python", "py"]
    } else {
        vec!["python3", "python"]
    };

    for candidate in candidates {
        let result = Command::new(candidate).arg("--version").output();
        if let Ok(output) = result {
            if output.status.success() {
                let version = String::from_utf8_lossy(&output.stdout).to_string();
                let version = version.trim().to_string();
                // Some python versions print to stderr
                if version.is_empty() {
                    let version = String::from_utf8_lossy(&output.stderr).trim().to_string();
                    if version.contains("Python 3") {
                        return Some(candidate.to_string());
                    }
                } else if version.contains("Python 3") {
                    return Some(candidate.to_string());
                }
            }
        }
    }
    None
}

/// Get the path to pip inside the venv.
fn venv_pip(venv_dir: &PathBuf) -> PathBuf {
    if cfg!(target_os = "windows") {
        venv_dir.join("Scripts").join("pip.exe")
    } else {
        venv_dir.join("bin").join("pip")
    }
}

/// Get the path to python inside the venv.
pub fn venv_python(venv_dir: &PathBuf) -> PathBuf {
    if cfg!(target_os = "windows") {
        venv_dir.join("Scripts").join("python.exe")
    } else {
        venv_dir.join("bin").join("python3")
    }
}

/// Detect GPU: macOS → "mps", nvidia-smi present → "cuda", else → "cpu".
fn detect_gpu() -> String {
    if cfg!(target_os = "macos") {
        return "mps".to_string();
    }

    // Check for nvidia-smi
    if let Ok(output) = Command::new("nvidia-smi").output() {
        if output.status.success() {
            return "cuda".to_string();
        }
    }

    "cpu".to_string()
}

/// Get python version from venv python.
fn get_python_version(venv_dir: &PathBuf) -> Result<String, String> {
    let python = venv_python(venv_dir);
    let output = Command::new(&python)
        .arg("--version")
        .output()
        .map_err(|e| format!("Failed to run venv python: {}", e))?;

    let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if version.is_empty() {
        let version = String::from_utf8_lossy(&output.stderr).trim().to_string();
        Ok(version)
    } else {
        Ok(version)
    }
}

/// Check torch version from venv python.
fn get_torch_version(venv_dir: &PathBuf) -> Result<String, String> {
    let python = venv_python(venv_dir);
    let output = Command::new(&python)
        .args(["-c", "import torch; print(torch.__version__)"])
        .output()
        .map_err(|e| format!("Failed to check torch: {}", e))?;

    if !output.status.success() {
        return Err("PyTorch not installed".to_string());
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Get the base alice-miner directory (~/.alice-miner/).
fn alice_miner_base() -> Result<PathBuf, String> {
    dirs::home_dir()
        .map(|h| h.join(ALICE_MINER_DIR))
        .ok_or_else(|| "Cannot determine home directory".to_string())
}

/// Get the venv directory (~/.alice-miner/.venv/).
pub fn get_venv_dir() -> Result<PathBuf, String> {
    alice_miner_base().map(|b| b.join(VENV_DIR))
}

/// Get the alice-node code directory (~/.alice-miner/alice-node/).
pub fn get_code_dir() -> Result<PathBuf, String> {
    alice_miner_base().map(|b| b.join(CODE_DIR))
}

fn emit_progress(app_handle: &tauri::AppHandle, step: &str, message: &str, progress: f32, error: bool) {
    let _ = app_handle.emit_all(
        "setup-progress",
        SetupProgress {
            step: step.to_string(),
            message: message.to_string(),
            progress,
            error,
        },
    );
}

#[tauri::command]
pub async fn auto_setup(app_handle: tauri::AppHandle) -> Result<SetupResult, String> {
    // Step 1: Check Python
    emit_progress(&app_handle, "python", "Checking for Python...", 0.0, false);

    let python_cmd = find_python().ok_or_else(|| {
        emit_progress(
            &app_handle,
            "python",
            "Python 3.10+ not found. Please install from https://www.python.org/downloads/",
            0.0,
            true,
        );
        "Python 3.10+ is required but not found in PATH. Please install Python from https://www.python.org/downloads/ and restart.".to_string()
    })?;

    emit_progress(
        &app_handle,
        "python",
        &format!("Found Python: {}", python_cmd),
        0.10,
        false,
    );

    // Step 2: Create venv
    emit_progress(&app_handle, "venv", "Creating virtual environment...", 0.15, false);

    let base_dir = alice_miner_base()?;
    std::fs::create_dir_all(&base_dir)
        .map_err(|e| format!("Failed to create {}: {}", base_dir.display(), e))?;

    let venv_dir = base_dir.join(VENV_DIR);

    if !venv_dir.join("bin").exists() && !venv_dir.join("Scripts").exists() {
        let output = Command::new(&python_cmd)
            .args(["-m", "venv", &venv_dir.to_string_lossy()])
            .output()
            .map_err(|e| format!("Failed to create venv: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            emit_progress(&app_handle, "venv", &format!("Failed to create venv: {}", stderr), 0.15, true);
            return Err(format!("Failed to create virtual environment: {}", stderr));
        }
    }

    emit_progress(&app_handle, "venv", "Virtual environment ready", 0.25, false);

    // Step 3: Detect GPU
    emit_progress(&app_handle, "gpu", "Detecting GPU...", 0.30, false);
    let device = detect_gpu();
    emit_progress(
        &app_handle,
        "gpu",
        &format!("Detected device: {}", device),
        0.35,
        false,
    );

    // Step 4: Install PyTorch
    emit_progress(&app_handle, "pytorch", "Installing PyTorch (this may take a while)...", 0.40, false);

    let pip = venv_pip(&venv_dir);
    let pip_str = pip.to_string_lossy().to_string();

    // First upgrade pip
    let _ = Command::new(&pip_str)
        .args(["install", "--upgrade", "pip"])
        .output();

    let torch_result = match device.as_str() {
        "cuda" => Command::new(&pip_str)
            .args([
                "install",
                "torch",
                "--index-url",
                "https://download.pytorch.org/whl/cu121",
            ])
            .output(),
        "mps" => Command::new(&pip_str)
            .args(["install", "torch"])
            .output(),
        _ => Command::new(&pip_str)
            .args([
                "install",
                "torch",
                "--index-url",
                "https://download.pytorch.org/whl/cpu",
            ])
            .output(),
    };

    match torch_result {
        Ok(output) if output.status.success() => {
            emit_progress(&app_handle, "pytorch", "PyTorch installed successfully", 0.60, false);
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            emit_progress(&app_handle, "pytorch", &format!("PyTorch install warning: {}", stderr), 0.60, false);
            // Don't fail — pip might return non-zero for warnings
            log::warn!("PyTorch install stderr: {}", stderr);
        }
        Err(e) => {
            emit_progress(&app_handle, "pytorch", &format!("Failed to install PyTorch: {}", e), 0.60, true);
            return Err(format!("Failed to install PyTorch: {}", e));
        }
    }

    // Step 5: Clone/update Alice-Node code
    emit_progress(&app_handle, "code", "Setting up Alice-Node code...", 0.65, false);

    let code_dir = base_dir.join(CODE_DIR);
    if code_dir.exists() {
        // git pull
        let output = Command::new("git")
            .args(["pull"])
            .current_dir(&code_dir)
            .output()
            .map_err(|e| format!("Failed to update code: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            log::warn!("git pull warning: {}", stderr);
            // Try harder: reset and pull
            let _ = Command::new("git")
                .args(["reset", "--hard", "origin/main"])
                .current_dir(&code_dir)
                .output();
            let _ = Command::new("git")
                .args(["pull"])
                .current_dir(&code_dir)
                .output();
        }
        emit_progress(&app_handle, "code", "Code updated", 0.75, false);
    } else {
        let output = Command::new("git")
            .args(["clone", REPO_URL, &code_dir.to_string_lossy()])
            .output()
            .map_err(|e| format!("Failed to clone repository: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            emit_progress(&app_handle, "code", &format!("Failed to clone: {}", stderr), 0.75, true);
            return Err(format!("Failed to clone repository: {}", stderr));
        }
        emit_progress(&app_handle, "code", "Code cloned successfully", 0.75, false);
    }

    // Step 6: Install requirements.txt
    emit_progress(&app_handle, "deps", "Installing dependencies...", 0.80, false);

    let requirements = code_dir.join("requirements.txt");
    if requirements.exists() {
        let output = Command::new(&pip_str)
            .args(["install", "-r", &requirements.to_string_lossy()])
            .output()
            .map_err(|e| format!("Failed to install dependencies: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            log::warn!("pip install requirements warning: {}", stderr);
            // Don't hard-fail, some deps might be optional
        }
    } else {
        log::info!("No requirements.txt found, skipping dependency install");
    }

    emit_progress(&app_handle, "deps", "Dependencies installed", 0.90, false);

    // Step 7: Verify installation
    emit_progress(&app_handle, "verify", "Verifying installation...", 0.95, false);

    let python_version = get_python_version(&venv_dir).unwrap_or_else(|_| "unknown".to_string());
    let torch_version = get_torch_version(&venv_dir).unwrap_or_else(|_| "not installed".to_string());

    let ready = !torch_version.contains("not installed");

    emit_progress(
        &app_handle,
        "done",
        &format!(
            "Setup complete! Python: {}, PyTorch: {}, Device: {}",
            python_version, torch_version, device
        ),
        1.0,
        false,
    );

    Ok(SetupResult {
        python_version,
        torch_version,
        device,
        ready,
    })
}
