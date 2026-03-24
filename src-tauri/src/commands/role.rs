use serde::{Deserialize, Serialize};

const KEYRING_SERVICE: &str = "alice-node";
const KEYRING_USER_ROLE: &str = "role";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoleInfo {
    pub role: String,
}

#[tauri::command]
pub fn save_role(role: String) -> Result<(), String> {
    let valid = matches!(role.as_str(), "trainer" | "scorer" | "aggregator");
    if !valid {
        return Err(format!("Invalid role: {}", role));
    }

    let entry =
        keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER_ROLE).map_err(|e| e.to_string())?;
    entry.set_password(&role).map_err(|e| e.to_string())?;

    log::info!("Role saved: {}", role);
    Ok(())
}

#[tauri::command]
pub fn get_role() -> Result<Option<String>, String> {
    let entry =
        keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER_ROLE).map_err(|e| e.to_string())?;

    match entry.get_password() {
        Ok(role) => Ok(Some(role)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
pub fn clear_role() -> Result<(), String> {
    let entry =
        keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER_ROLE).map_err(|e| e.to_string())?;

    match entry.delete_password() {
        Ok(_) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}
