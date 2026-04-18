//! WebSocket Plugin for Dimensional Viewer
//!
//! Handles connection to the dimensional-viewer server and dispatches view updates.

use bevy::prelude::*;
use ewebsock::{WsEvent, WsMessage, WsReceiver, WsSender};
use std::sync::{Arc, Mutex};

use crate::models::ViewResponse;

/// Resource holding the current view state
#[derive(Resource)]
pub struct ViewState {
    pub response: ViewResponse,
    pub connected: bool,
    pub last_update: f64,
}

impl Default for ViewState {
    fn default() -> Self {
        Self {
            response: ViewResponse::default(),
            connected: false,
            last_update: 0.0,
        }
    }
}

/// Resource for WebSocket connection
#[derive(Resource)]
pub struct WebSocketConnection {
    sender: Option<WsSender>,
    receiver: Option<WsReceiver>,
    pending_responses: Arc<Mutex<Vec<ViewResponse>>>,
}

impl Default for WebSocketConnection {
    fn default() -> Self {
        Self {
            sender: None,
            receiver: None,
            pending_responses: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

/// Event fired when view updates
#[derive(Event)]
pub struct ViewUpdatedEvent;

pub struct WebSocketPlugin;

impl Plugin for WebSocketPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<ViewState>()
            .init_resource::<WebSocketConnection>()
            .add_event::<ViewUpdatedEvent>()
            .add_systems(Startup, setup_websocket)
            .add_systems(Update, (poll_websocket, process_responses).chain());
    }
}

/// Get WebSocket URL based on current page location
fn get_ws_url() -> String {
    if let Some(window) = web_sys::window() {
        if let Ok(location) = window.location().href() {
            let ws_url = location
                .replace("http://", "ws://")
                .replace("https://", "wss://");

            let base: String = ws_url.split('/').take(3).collect::<Vec<_>>().join("/");
            if !base.is_empty() {
                return format!("{}/ws", base);
            }
        }
    }

    "ws://localhost:8750/ws".to_string()
}

/// Initialize WebSocket connection
fn setup_websocket(mut connection: ResMut<WebSocketConnection>) {
    let url = get_ws_url();
    tracing::info!("Connecting to WebSocket: {}", url);

    match ewebsock::connect(&url, ewebsock::Options::default()) {
        Ok((sender, receiver)) => {
            connection.sender = Some(sender);
            connection.receiver = Some(receiver);
            tracing::info!("WebSocket connection established");
        }
        Err(e) => {
            tracing::error!("Failed to connect WebSocket: {}", e);
        }
    }
}

/// Poll WebSocket for incoming messages
fn poll_websocket(mut connection: ResMut<WebSocketConnection>, mut view_state: ResMut<ViewState>) {
    let Some(receiver) = &mut connection.receiver else {
        return;
    };

    while let Some(event) = receiver.try_recv() {
        match event {
            WsEvent::Opened => {
                tracing::info!("WebSocket opened");
                view_state.connected = true;
            }
            WsEvent::Message(msg) => match msg {
                WsMessage::Text(text) => match serde_json::from_str::<ViewResponse>(&text) {
                    Ok(response) => {
                        if let Ok(mut pending) = connection.pending_responses.lock() {
                            pending.push(response);
                        }
                    }
                    Err(e) => {
                        tracing::warn!("Failed to parse ViewResponse: {}", e);
                    }
                },
                WsMessage::Binary(data) => match serde_json::from_slice::<ViewResponse>(&data) {
                    Ok(response) => {
                        if let Ok(mut pending) = connection.pending_responses.lock() {
                            pending.push(response);
                        }
                    }
                    Err(e) => {
                        tracing::warn!("Failed to parse binary ViewResponse: {}", e);
                    }
                },
                _ => {}
            },
            WsEvent::Error(e) => {
                tracing::error!("WebSocket error: {}", e);
                view_state.connected = false;
            }
            WsEvent::Closed => {
                tracing::info!("WebSocket closed");
                view_state.connected = false;
            }
        }
    }
}

/// Process pending ViewResponse updates
fn process_responses(
    connection: Res<WebSocketConnection>,
    mut view_state: ResMut<ViewState>,
    mut events: EventWriter<ViewUpdatedEvent>,
    time: Res<Time>,
) {
    let responses: Vec<ViewResponse> = {
        if let Ok(mut pending) = connection.pending_responses.lock() {
            std::mem::take(&mut *pending)
        } else {
            return;
        }
    };

    // Take the latest response
    if let Some(response) = responses.into_iter().last() {
        tracing::debug!(
            "Received view: {} layers, {} points, {:.2} coherence",
            response.layers.len(),
            response.metadata.points_displayed,
            response.metadata.avg_coherence
        );

        view_state.response = response;
        view_state.last_update = time.elapsed_seconds_f64();
        events.send(ViewUpdatedEvent);
    }
}
