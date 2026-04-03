//! GaiaOS Dimensional Viewer - Bevy WASM Client
//!
//! Visualizes 8D→3D quantum projections with coherence and virtue indicators.
//! Connects to the dimensional-viewer server via WebSocket for real-time updates.

use bevy::prelude::*;
use wasm_bindgen::prelude::*;

mod camera_plugin;
mod models;
mod ui_plugin;
mod visualization_plugin;
mod websocket_plugin;

use camera_plugin::CameraPlugin;
use ui_plugin::UiPlugin;
use visualization_plugin::VisualizationPlugin;
use websocket_plugin::WebSocketPlugin;

/// WASM entry point
#[wasm_bindgen(start)]
pub fn main() {
    // Set up panic hook for better error messages
    console_error_panic_hook::set_once();

    // Initialize tracing for WASM
    tracing_wasm::set_as_global_default();

    tracing::info!("Starting GaiaOS Dimensional Viewer");

    App::new()
        // Bevy defaults for WASM
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "GaiaOS Dimensional Viewer".to_string(),
                canvas: Some("#dimensional-canvas".to_string()),
                fit_canvas_to_parent: true,
                prevent_default_event_handling: true,
                ..default()
            }),
            ..default()
        }))
        // Custom plugins
        .add_plugins((WebSocketPlugin, VisualizationPlugin, CameraPlugin, UiPlugin))
        .run();
}
