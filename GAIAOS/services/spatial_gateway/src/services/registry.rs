//! Cell Registry Service
//!
//! Manages cell sessions, authentication, and capability tracking.
//! Each cell that connects gets a session with negotiated QoS parameters.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::model::cell::{CellCapability, CellDomain, CellSession, QosParams};
use crate::model::vqbit::Vqbit8D;

/// Cell registry - manages all connected cells
#[derive(Clone)]
pub struct CellRegistry {
    /// Active sessions by cell_id
    sessions: Arc<RwLock<HashMap<Uuid, CellSession>>>,
    /// Cell last known positions
    positions: Arc<RwLock<HashMap<Uuid, Vqbit8D>>>,
}

impl Default for CellRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl CellRegistry {
    /// Create a new empty registry
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            positions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Register a new cell session
    pub async fn register(
        &self,
        cell_id: Uuid,
        domain: CellDomain,
        capabilities: Vec<CellCapability>,
    ) -> CellSession {
        let session_id = Uuid::new_v4();
        let now = Vqbit8D::now_unix();

        let session = CellSession {
            cell_id,
            session_id,
            domain,
            capabilities,
            qos: QosParams::default(),
            connected_at: now,
            last_activity: now,
        };

        self.sessions.write().await.insert(cell_id, session.clone());

        tracing::info!(
            "Registered cell {} (session {}) domain={:?}",
            cell_id,
            session_id,
            session.domain
        );

        session
    }

    /// Get a cell session by ID
    #[allow(dead_code)]
    pub async fn get(&self, cell_id: &Uuid) -> Option<CellSession> {
        self.sessions.read().await.get(cell_id).cloned()
    }

    /// Get a cell session by session ID
    #[allow(dead_code)]
    pub async fn get_by_session(&self, session_id: &Uuid) -> Option<CellSession> {
        self.sessions
            .read()
            .await
            .values()
            .find(|s| s.session_id == *session_id)
            .cloned()
    }

    /// Update last activity timestamp for a cell
    #[allow(dead_code)]
    pub async fn touch(&self, cell_id: &Uuid) {
        if let Some(session) = self.sessions.write().await.get_mut(cell_id) {
            session.last_activity = Vqbit8D::now_unix();
        }
    }

    /// Update last known position for a cell
    #[allow(dead_code)]
    pub async fn update_position(&self, cell_id: &Uuid, position: Vqbit8D) {
        self.positions.write().await.insert(*cell_id, position);
        self.touch(cell_id).await;
    }

    /// Get last known position for a cell
    #[allow(dead_code)]
    pub async fn get_position(&self, cell_id: &Uuid) -> Option<Vqbit8D> {
        self.positions.read().await.get(cell_id).cloned()
    }

    /// Remove a cell session
    pub async fn unregister(&self, cell_id: &Uuid) {
        self.sessions.write().await.remove(cell_id);
        self.positions.write().await.remove(cell_id);
        tracing::info!("Unregistered cell {}", cell_id);
    }

    /// Get all cells in a domain
    #[allow(dead_code)]
    pub async fn get_by_domain(&self, domain: &CellDomain) -> Vec<CellSession> {
        self.sessions
            .read()
            .await
            .values()
            .filter(|s| &s.domain == domain)
            .cloned()
            .collect()
    }

    /// Get all active sessions
    pub async fn all_sessions(&self) -> Vec<CellSession> {
        self.sessions.read().await.values().cloned().collect()
    }

    /// Get count of active sessions
    pub async fn session_count(&self) -> usize {
        self.sessions.read().await.len()
    }

    /// Prune inactive sessions (older than threshold_secs)
    pub async fn prune_inactive(&self, threshold_secs: f64) -> usize {
        let now = Vqbit8D::now_unix();
        let mut sessions = self.sessions.write().await;
        let mut positions = self.positions.write().await;

        let inactive: Vec<Uuid> = sessions
            .iter()
            .filter(|(_, s)| now - s.last_activity > threshold_secs)
            .map(|(id, _)| *id)
            .collect();

        let count = inactive.len();
        for id in inactive {
            sessions.remove(&id);
            positions.remove(&id);
            tracing::info!("Pruned inactive cell {}", id);
        }

        count
    }
}

/// Parse domain string to CellDomain enum
pub fn parse_domain(s: &str) -> CellDomain {
    match s.to_uppercase().as_str() {
        "ATC" => CellDomain::Atc,
        "AV" => CellDomain::Av,
        "MARITIME" => CellDomain::Maritime,
        "WEATHER" => CellDomain::Weather,
        "GAME" => CellDomain::Game,
        "GENERAL" => CellDomain::General,
        _ => CellDomain::Unknown,
    }
}

/// Parse capability string to CellCapability enum
pub fn parse_capability(s: &str) -> CellCapability {
    match s.to_lowercase().as_str() {
        "pose" => CellCapability::Pose,
        "imu" => CellCapability::Imu,
        "radar" => CellCapability::Radar,
        "lidar" => CellCapability::Lidar,
        "camera" => CellCapability::Camera,
        "gps" => CellCapability::Gps,
        "actuator" => CellCapability::Actuator,
        "inference" => CellCapability::Inference,
        other => CellCapability::Custom(other.to_string()),
    }
}
