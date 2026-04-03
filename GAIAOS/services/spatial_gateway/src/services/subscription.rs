//! Subscription Service
//!
//! Manages streaming subscriptions for cells that want continuous
//! updates about regions of the truth field.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::model::messages::{QueryPayload, QueryResultSample};

/// A subscription to truth field updates
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Subscription {
    /// Unique subscription ID
    pub id: String,
    /// Cell that owns this subscription
    pub cell_id: Uuid,
    /// Query defining the subscription region
    pub query: QueryPayload,
    /// Target update frequency in Hz
    pub update_hz: u32,
    /// Created timestamp
    pub created_at: f64,
    /// Last update sent timestamp
    pub last_update: f64,
}

/// Subscription manager
#[derive(Clone)]
pub struct SubscriptionManager {
    /// Active subscriptions by ID
    subscriptions: Arc<RwLock<HashMap<String, Subscription>>>,
    /// Subscriptions by cell ID
    by_cell: Arc<RwLock<HashMap<Uuid, Vec<String>>>>,
}

impl Default for SubscriptionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[allow(dead_code)]
impl SubscriptionManager {
    /// Create a new subscription manager
    pub fn new() -> Self {
        Self {
            subscriptions: Arc::new(RwLock::new(HashMap::new())),
            by_cell: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Add a subscription
    pub async fn subscribe(
        &self,
        id: String,
        cell_id: Uuid,
        query: QueryPayload,
        update_hz: Option<u32>,
    ) -> Subscription {
        let now = crate::model::vqbit::Vqbit8D::now_unix();

        let sub = Subscription {
            id: id.clone(),
            cell_id,
            query,
            update_hz: update_hz.unwrap_or(1),
            created_at: now,
            last_update: now,
        };

        // Add to main store
        self.subscriptions
            .write()
            .await
            .insert(id.clone(), sub.clone());

        // Add to cell index
        self.by_cell
            .write()
            .await
            .entry(cell_id)
            .or_insert_with(Vec::new)
            .push(id);

        tracing::info!("Added subscription {} for cell {}", sub.id, cell_id);

        sub
    }

    /// Remove a subscription
    pub async fn unsubscribe(&self, id: &str) -> bool {
        if let Some(sub) = self.subscriptions.write().await.remove(id) {
            // Remove from cell index
            if let Some(subs) = self.by_cell.write().await.get_mut(&sub.cell_id) {
                subs.retain(|s| s != id);
            }
            tracing::info!("Removed subscription {}", id);
            true
        } else {
            false
        }
    }

    /// Remove all subscriptions for a cell
    pub async fn unsubscribe_cell(&self, cell_id: &Uuid) -> usize {
        let sub_ids: Vec<String> = self
            .by_cell
            .write()
            .await
            .remove(cell_id)
            .unwrap_or_default();

        let count = sub_ids.len();

        let mut subs = self.subscriptions.write().await;
        for id in sub_ids {
            subs.remove(&id);
        }

        if count > 0 {
            tracing::info!("Removed {} subscriptions for cell {}", count, cell_id);
        }

        count
    }

    /// Get all subscriptions for a cell
    pub async fn get_for_cell(&self, cell_id: &Uuid) -> Vec<Subscription> {
        let sub_ids = self
            .by_cell
            .read()
            .await
            .get(cell_id)
            .cloned()
            .unwrap_or_default();

        let subs = self.subscriptions.read().await;
        sub_ids
            .iter()
            .filter_map(|id| subs.get(id).cloned())
            .collect()
    }

    /// Get a specific subscription
    pub async fn get(&self, id: &str) -> Option<Subscription> {
        self.subscriptions.read().await.get(id).cloned()
    }

    /// Update last_update timestamp for a subscription
    pub async fn mark_updated(&self, id: &str) {
        if let Some(sub) = self.subscriptions.write().await.get_mut(id) {
            sub.last_update = crate::model::vqbit::Vqbit8D::now_unix();
        }
    }

    /// Get all subscriptions that need updates
    /// Returns subscriptions where (now - last_update) >= (1.0 / update_hz)
    pub async fn get_due_for_update(&self) -> Vec<Subscription> {
        let now = crate::model::vqbit::Vqbit8D::now_unix();

        self.subscriptions
            .read()
            .await
            .values()
            .filter(|s| {
                let interval = 1.0 / s.update_hz as f64;
                now - s.last_update >= interval
            })
            .cloned()
            .collect()
    }

    /// Check if a sample matches a subscription's query
    pub fn sample_matches_query(sample: &QueryResultSample, query: &QueryPayload) -> bool {
        // Domain filter
        if let Some(ref domain) = query.domain {
            if sample.domain.to_uppercase() != domain.to_uppercase() {
                return false;
            }
        }

        // Spatial bounds (d0_x = east/lon, d1_y = north/lat)
        let in_lon = sample.vqbit.d0_x >= query.lon_min && sample.vqbit.d0_x <= query.lon_max;
        let in_lat = sample.vqbit.d1_y >= query.lat_min && sample.vqbit.d1_y <= query.lat_max;

        if !in_lon || !in_lat {
            return false;
        }

        // Temporal bounds
        if let Some(t_min) = query.t_min {
            if sample.ts_unix < t_min {
                return false;
            }
        }
        if let Some(t_max) = query.t_max {
            if sample.ts_unix > t_max {
                return false;
            }
        }

        true
    }

    /// Get subscription count
    pub async fn count(&self) -> usize {
        self.subscriptions.read().await.len()
    }
}
