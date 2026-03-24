use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::io::AsyncWriteExt;

const DL_URL: &str = "https://dl.aliceprotocol.org";
const MAX_FILE_SIZE: u64 = 20 * 1024 * 1024 * 1024; // 20 GB

/// Concurrency guard: only one download at a time
static DOWNLOADING: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum ModelVariant {
    Int8,  // Legacy alias — maps to latest model
    Fp16,  // Legacy alias — maps to latest model
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelStatus {
    pub int8_available: bool,
    pub fp16_available: bool,
    pub int8_size_gb: f64,
    pub fp16_size_gb: f64,
    pub active_variant: Option<ModelVariant>,
    pub model_version: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {
    pub variant: ModelVariant,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub percent: f64,
    pub speed_mbps: f64,
}

// Global download progress (thread-safe)
static DOWNLOAD_PROGRESS: AtomicU64 = AtomicU64::new(0);
static DOWNLOAD_TOTAL: AtomicU64 = AtomicU64::new(0);

fn get_model_dir() -> std::path::PathBuf {
    let home = dirs::home_dir().unwrap_or_default();
    let model_dir = home.join(".alice-miner").join("models");
    std::fs::create_dir_all(&model_dir).ok();
    model_dir
}

fn get_model_path(_variant: ModelVariant) -> std::path::PathBuf {
    get_model_dir().join("model_current.pt")
}

fn get_version_path() -> std::path::PathBuf {
    get_model_dir().join("version.txt")
}

fn read_local_version() -> Option<u32> {
    let path = get_version_path();
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

fn write_local_version(version: u32) {
    let path = get_version_path();
    std::fs::write(&path, version.to_string()).ok();
}

/// Fetch the latest model version from the server
async fn fetch_latest_version(client: &reqwest::Client) -> Result<u32, String> {
    let url = format!("{}/latest_version.txt", DL_URL);
    let resp = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("Failed to fetch latest version: HTTP {}", resp.status()));
    }
    let text = resp.text().await.map_err(|e| e.to_string())?;
    text.trim()
        .parse::<u32>()
        .map_err(|e| format!("Invalid version number: {}", e))
}

#[tauri::command]
pub fn check_model_status() -> Result<ModelStatus, String> {
    let model_path = get_model_dir().join("model_current.pt");
    let available = model_path.exists();

    let size_gb = if available {
        std::fs::metadata(&model_path)
            .map(|m| m.len() as f64 / 1e9)
            .unwrap_or(0.0)
    } else {
        0.0
    };

    let model_version = read_local_version();

    Ok(ModelStatus {
        int8_available: available,
        fp16_available: available,
        int8_size_gb: size_gb,
        fp16_size_gb: size_gb,
        active_variant: if available { Some(ModelVariant::Fp16) } else { None },
        model_version,
    })
}

#[tauri::command]
pub async fn download_model(variant: ModelVariant) -> Result<(), String> {
    // Concurrency guard: prevent multiple simultaneous downloads
    if DOWNLOADING.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
        return Err("A download is already in progress".to_string());
    }

    // Ensure we clear the download flag on any exit path
    let result = download_model_inner(variant).await;
    DOWNLOADING.store(false, Ordering::SeqCst);
    result
}

async fn download_model_inner(_variant: ModelVariant) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(7200)) // 2 hour timeout for 13GB
        .build()
        .map_err(|e| e.to_string())?;

    // 1. Fetch latest version
    let latest_version = fetch_latest_version(&client).await?;
    let local_version = read_local_version();

    log::info!(
        "Model version: latest=v{}, local={:?}",
        latest_version,
        local_version
    );

    // If already up to date, skip download
    let model_path = get_model_dir().join("model_current.pt");
    if let Some(local_v) = local_version {
        if local_v >= latest_version && model_path.exists() {
            log::info!("Model already up to date (v{})", local_v);
            return Ok(());
        }
    }

    // 2. Try delta update first (much smaller)
    if let Some(local_v) = local_version {
        if local_v + 1 == latest_version {
            let delta_url = format!("{}/v{}_delta.pt.zstd", DL_URL, latest_version);
            log::info!("Attempting delta update: {}", delta_url);
            let resp = client.head(&delta_url).send().await;
            if let Ok(r) = resp {
                if r.status().is_success() {
                    log::info!("Delta available, but full download is more reliable for GUI. Skipping delta.");
                    // TODO: implement delta apply (zstd decompress + merge)
                }
            }
        }
    }

    // 3. Full download: v{N}_full.pt
    let filename = format!("v{}_full.pt", latest_version);
    let url = format!("{}/{}", DL_URL, filename);
    let temp_path = model_path.with_extension("pt.tmp");

    log::info!("Starting download: {} -> {:?}", url, model_path);

    // Check for existing partial download
    let existing_size = if temp_path.exists() {
        std::fs::metadata(&temp_path)
            .map(|m| m.len())
            .unwrap_or(0)
    } else {
        0
    };

    // Build request with Range header for resume
    let mut request = client.get(&url);
    if existing_size > 0 {
        request = request.header("Range", format!("bytes={}-", existing_size));
        log::info!("Resuming download from {} bytes", existing_size);
    }

    let response = request.send().await.map_err(|e| e.to_string())?;

    if !response.status().is_success() && response.status() != reqwest::StatusCode::PARTIAL_CONTENT
    {
        return Err(format!(
            "Download failed: HTTP {} for {}",
            response.status(),
            url
        ));
    }

    // #12: If we requested a Range but got 200 (not 206), server ignored Range header
    let server_ignored_range = existing_size > 0 && response.status() == reqwest::StatusCode::OK;
    if server_ignored_range {
        log::warn!("Server ignored Range header, restarting download from scratch");
        // Truncate the file and start over
        let _ = std::fs::remove_file(&temp_path);
    }

    let content_length = response.content_length().unwrap_or(0);
    let base_offset = if server_ignored_range { 0 } else { existing_size };
    let total_size = content_length + base_offset;

    // #12: Enforce max file size limit (20 GB)
    if total_size > MAX_FILE_SIZE {
        return Err(format!(
            "File size {} bytes exceeds maximum allowed {} bytes (20 GB)",
            total_size, MAX_FILE_SIZE
        ));
    }

    DOWNLOAD_TOTAL.store(total_size, Ordering::SeqCst);
    DOWNLOAD_PROGRESS.store(base_offset, Ordering::SeqCst);

    // Open file: truncate if server ignored range, append otherwise
    let mut file = if server_ignored_range {
        tokio::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&temp_path)
            .await
            .map_err(|e| e.to_string())?
    } else {
        tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&temp_path)
            .await
            .map_err(|e| e.to_string())?
    };

    let mut stream = response.bytes_stream();
    let mut downloaded = base_offset;

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| e.to_string())?;
        downloaded += chunk.len() as u64;

        // Enforce size limit during download
        if downloaded > MAX_FILE_SIZE {
            let _ = std::fs::remove_file(&temp_path);
            return Err(format!(
                "Download exceeded maximum file size of {} bytes (20 GB)",
                MAX_FILE_SIZE
            ));
        }

        file.write_all(&chunk).await.map_err(|e| e.to_string())?;
        DOWNLOAD_PROGRESS.store(downloaded, Ordering::SeqCst);
    }

    file.flush().await.map_err(|e| e.to_string())?;
    drop(file);

    // #11: Verify checksum — strict mode
    let checksum_url = format!("{}/v{}_full.pt.sha256", DL_URL, latest_version);
    log::info!("Fetching checksum from: {}", checksum_url);
    let mut verified = false;
    match client.get(&checksum_url).send().await {
        Ok(resp) if resp.status().is_success() => {
            let expected_hash = resp
                .text()
                .await
                .map_err(|e| e.to_string())?
                .trim()
                .split_whitespace()
                .next()
                .unwrap_or("")
                .to_lowercase();

            if !expected_hash.is_empty() {
                log::info!("Verifying checksum...");
                let file_bytes = std::fs::read(&temp_path).map_err(|e| e.to_string())?;
                let mut hasher = Sha256::new();
                hasher.update(&file_bytes);
                let actual_hash = format!("{:x}", hasher.finalize());

                if actual_hash != expected_hash {
                    // Checksum exists but doesn't match — MUST delete and error
                    let _ = std::fs::remove_file(&temp_path);
                    return Err(format!(
                        "Checksum mismatch: expected {}, got {}. Corrupted file deleted.",
                        expected_hash, actual_hash
                    ));
                }
                log::info!("Checksum verified OK");
                verified = true;
            }
        }
        Ok(resp) => {
            // Checksum file not available — warn but allow model to be used
            log::warn!(
                "Checksum file not available (HTTP {}), model usable but unverified",
                resp.status()
            );
        }
        Err(e) => {
            // Network error fetching checksum — warn but allow model to be used
            log::warn!(
                "Could not fetch checksum: {}, model usable but unverified",
                e
            );
        }
    }

    if !verified {
        log::warn!("Model downloaded but checksum could not be verified (verified=false)");
    }

    // Rename temp to final
    std::fs::rename(&temp_path, &model_path).map_err(|e| e.to_string())?;

    // Write version file
    write_local_version(latest_version);

    log::info!(
        "Download complete: v{} -> {:?}",
        latest_version,
        model_path
    );
    Ok(())
}

#[tauri::command]
pub fn get_download_progress() -> Result<Option<DownloadProgress>, String> {
    let downloaded = DOWNLOAD_PROGRESS.load(Ordering::SeqCst);
    let total = DOWNLOAD_TOTAL.load(Ordering::SeqCst);

    if total == 0 {
        return Ok(None);
    }

    let percent = (downloaded as f64 / total as f64) * 100.0;

    Ok(Some(DownloadProgress {
        variant: ModelVariant::Fp16,
        downloaded_bytes: downloaded,
        total_bytes: total,
        percent,
        speed_mbps: 0.0, // TODO: calculate speed
    }))
}
