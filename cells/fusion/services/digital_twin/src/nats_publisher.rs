/*!
 * NATS Publisher for ATC World State
 *
 * Standardized NATS subjects for ATC organism:
 * - gaia.atc.world_state.snapshot - Full world state (periodic)
 * - gaia.atc.world_state.delta - Per-tick changes (high frequency)
 * - gaia.atc.alerts.conflicts - Conflict events
 * - gaia.atc.metrics.performance - Performance metrics
 */

use async_nats::Client;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::time::Instant;

/// Complete ATC world state snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AtcWorldState {
    pub timestamp: String,
    pub unix_ts: u64,
    pub aircraft: Vec<AircraftEntity>,
    pub conflicts: Vec<ConflictPair>,
    pub performance: PerformanceMetrics,
}

/// Aircraft entity for frontend consumption
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AircraftEntity {
    pub id: String,
    pub callsign: String,
    pub flight_number: String,
    pub lat: f64,
    pub lon: f64,
    pub alt_m: f64,
    pub heading_deg_true: f64,
    pub ground_speed_kts: f64,
    pub wind_direction_deg_true: f64,
    pub wind_speed_kts: f64,
    pub wind_opacity: f32,
    pub is_inside_own_bubble_safe: bool,
    pub has_conflict: bool,
    pub safety_bubble_radius_m: f64,
}

/// Detected conflict pair
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConflictPair {
    pub aircraft_a: String,
    pub aircraft_b: String,
    pub horizontal_separation_m: f64,
    pub vertical_separation_m: f64,
    pub time_to_closest_approach_s: f64,
    pub severity: ConflictSeverity,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ConflictSeverity {
    Advisory,  // Within bubble but not critical
    Warning,   // Separation below standard
    Critical,  // Immediate risk
}

/// Performance metrics for the ATC system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub aircraft_count: usize,
    pub conflicts_detected: usize,
    pub tick_duration_ms: f64,
    pub fps: f64,
}

/// NATS subject constants
pub const SUBJECT_WORLD_SNAPSHOT: &str = "gaia.atc.world_state.snapshot";
pub const SUBJECT_WORLD_DELTA: &str = "gaia.atc.world_state.delta";
pub const SUBJECT_CONFLICTS: &str = "gaia.atc.alerts.conflicts";
pub const SUBJECT_METRICS: &str = "gaia.atc.metrics.performance";

/// Publish complete world state snapshot
pub async fn publish_world_state(
    nats: &Client,
    state: &AtcWorldState,
) -> anyhow::Result<()> {
    let payload = serde_json::to_vec(state)?;
    nats.publish(SUBJECT_WORLD_SNAPSHOT, payload.into()).await?;
    Ok(())
}

/// Publish conflict alerts
pub async fn publish_conflicts(
    nats: &Client,
    conflicts: &[ConflictPair],
) -> anyhow::Result<()> {
    let payload = serde_json::to_vec(conflicts)?;
    nats.publish(SUBJECT_CONFLICTS, payload.into()).await?;
    Ok(())
}

/// Publish performance metrics
pub async fn publish_metrics(
    nats: &Client,
    metrics: &PerformanceMetrics,
) -> anyhow::Result<()> {
    let payload = serde_json::to_vec(metrics)?;
    nats.publish(SUBJECT_METRICS, payload.into()).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_subject_format() {
        assert_eq!(SUBJECT_WORLD_SNAPSHOT, "gaia.atc.world_state.snapshot");
        assert_eq!(SUBJECT_CONFLICTS, "gaia.atc.alerts.conflicts");
    }
}
