#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

mod commands;
mod services;

use tauri::{Manager, SystemTray, SystemTrayEvent, SystemTrayMenu, CustomMenuItem};

fn main() {
    env_logger::init();

    // System tray menu
    let quit = CustomMenuItem::new("quit".to_string(), "Quit");
    let show = CustomMenuItem::new("show".to_string(), "Show Window");
    let tray_menu = SystemTrayMenu::new()
        .add_item(show)
        .add_native_item(tauri::SystemTrayMenuItem::Separator)
        .add_item(quit);

    let system_tray = SystemTray::new().with_menu(tray_menu);

    tauri::Builder::default()
        .system_tray(system_tray)
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::LeftClick { .. } => {
                if let Some(window) = app.get_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
                "quit" => {
                    // Stop all child processes before exiting
                    if let Some(mining_state) = app.try_state::<commands::mining::MiningProcessState>() {
                        if let Ok(mut process) = mining_state.lock() {
                            if let Some(ref mut child) = process.child {
                                let _ = child.kill();
                            }
                        }
                    }
                    if let Some(scoring_state) = app.try_state::<commands::scoring::ScoringProcessState>() {
                        if let Ok(mut process) = scoring_state.lock() {
                            if let Some(ref mut child) = process.child {
                                let _ = child.kill();
                            }
                        }
                    }
                    if let Some(agg_state) = app.try_state::<commands::aggregating::AggregatingProcessState>() {
                        if let Ok(mut process) = agg_state.lock() {
                            if let Some(ref mut child) = process.child {
                                let _ = child.kill();
                            }
                        }
                    }
                    app.exit(0);
                }
                "show" => {
                    if let Some(window) = app.get_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                _ => {}
            },
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            // Network
            commands::network::diagnose_network,
            commands::network::check_ps_status,
            // GPU
            commands::gpu::detect_gpu,
            commands::gpu::get_gpu_stats,
            // Wallet
            commands::wallet::generate_wallet,
            commands::wallet::import_wallet,
            commands::wallet::save_wallet_address,
            commands::wallet::get_wallet_address,
            commands::wallet::clear_wallet,
            // Mining
            commands::mining::start_mining,
            commands::mining::stop_mining,
            commands::mining::get_mining_status,
            // Model
            commands::model::check_model_status,
            commands::model::download_model,
            commands::model::get_download_progress,
            // Role
            commands::role::save_role,
            commands::role::get_role,
            commands::role::clear_role,
            // Scoring
            commands::scoring::start_scoring,
            commands::scoring::stop_scoring,
            commands::scoring::get_scoring_status,
            // Aggregating
            commands::aggregating::start_aggregating,
            commands::aggregating::stop_aggregating,
            commands::aggregating::get_aggregating_status,
            // Staking
            commands::staking::stake,
            commands::staking::unstake,
            commands::staking::get_staking_info,
            // Setup
            commands::setup::auto_setup,
        ])
        .manage(std::sync::Mutex::new(commands::mining::MiningProcess::default()))
        .manage(std::sync::Mutex::new(commands::scoring::ScoringProcess::default()))
        .manage(std::sync::Mutex::new(commands::aggregating::AggregatingProcess::default()))
        .setup(|app| {
            // Initialize services
            let app_handle = app.handle();
            
            // Check for updates on startup
            tauri::async_runtime::spawn(async move {
                if let Err(e) = services::updater::check_for_updates(&app_handle).await {
                    log::warn!("Update check failed: {}", e);
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
