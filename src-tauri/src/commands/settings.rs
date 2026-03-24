use serde::{Deserialize, Serialize};
use std::path::PathBuf;

const ALICE_MINER_DIR: &str = ".alice-miner";
const SETTINGS_FILE: &str = "settings.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    #[serde(default)]
    pub language: String,
    #[serde(default)]
    pub auto_start: bool,
    #[serde(default)]
    pub notifications: bool,
    #[serde(default = "default_ps_url")]
    pub ps_url: String,
    #[serde(default)]
    pub device: String,
}

fn default_ps_url() -> String {
    "https://ps.aliceprotocol.org".to_string()
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            language: "en".to_string(),
            auto_start: false,
            notifications: true,
            ps_url: default_ps_url(),
            device: String::new(),
        }
    }
}

fn settings_path() -> Result<PathBuf, String> {
    let home = dirs::home_dir().ok_or("Cannot determine home directory")?;
    let dir = home.join(ALICE_MINER_DIR);
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create settings directory: {}", e))?;
    Ok(dir.join(SETTINGS_FILE))
}

#[tauri::command]
pub fn save_settings(settings: AppSettings) -> Result<(), String> {
    let path = settings_path()?;
    let json = serde_json::to_string_pretty(&settings)
        .map_err(|e| format!("Failed to serialize settings: {}", e))?;
    std::fs::write(&path, json)
        .map_err(|e| format!("Failed to write settings: {}", e))?;
    log::info!("Settings saved to {:?}", path);
    Ok(())
}

#[tauri::command]
pub fn load_settings() -> Result<AppSettings, String> {
    let path = settings_path()?;
    if !path.exists() {
        return Ok(AppSettings::default());
    }
    let content = std::fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read settings: {}", e))?;
    let settings: AppSettings = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse settings: {}", e))?;
    Ok(settings)
}

/// Load the PS URL from settings, falling back to the default.
pub fn load_ps_url() -> String {
    match load_settings() {
        Ok(s) if !s.ps_url.is_empty() => s.ps_url,
        _ => default_ps_url(),
    }
}
