//! GaiaOS ATC Measurement Policy Engine
//! 
//! Production-ready credit management and prediction system for OpenSky integration.
//! - Minimizes OpenSky credit usage
//! - Prefers /states/own when available
//! - Schedules /states/all by region based on credit exhaustion
//! - Tracks uncertainty growth per aircraft
//! - Emits clean events for Spatial Gateway → UUM8D

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::time::{Duration, Instant};

/// Credits consumed per /states/all call by bounding box size.
/// These values come directly from OpenSky documentation.
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub enum AreaCredits {
    Small = 1,      // <500x500km
    Medium = 2,     // <1000x1000km
    Large = 3,      // <2000x2000km
    Global = 4,     // entire globe
}

impl Default for AreaCredits {
    fn default() -> Self {
        AreaCredits::Small
    }
}

/// Polling decision classification for each region.
#[derive(Clone, Debug, PartialEq)]
pub enum PollDecision {
    /// Safe to poll this box now.
    PollNow,
    /// Skip for now; credits too low or interval not elapsed.
    Skip,
    /// Emergency only: credits nearly exhausted.
    Critical,
}

/// Stores credit usage + scheduling state.
#[derive(Debug, Clone)]
pub struct CreditManager {
    pub daily_credit_limit: u32,
    pub credits_used_today: u32,
    pub next_reset_at: DateTime<Utc>,
    pub requests_today: u32,
}

impl CreditManager {
    pub fn new(limit: u32) -> Self {
        Self {
            daily_credit_limit: limit,
            credits_used_today: 0,
            next_reset_at: Utc::now() + chrono::Duration::hours(24),
            requests_today: 0,
        }
    }

    /// Reset credits if we've crossed into a new day period.
    pub fn maybe_reset(&mut self) {
        let now = Utc::now();
        if now >= self.next_reset_at {
            tracing::info!(
                "Credit reset: {} credits used in {} requests yesterday",
                self.credits_used_today,
                self.requests_today
            );
            self.credits_used_today = 0;
            self.requests_today = 0;
            self.next_reset_at = now + chrono::Duration::hours(24);
        }
    }

    pub fn can_spend(&self, cost: AreaCredits) -> bool {
        self.credits_used_today + cost as u32 <= self.daily_credit_limit
    }

    pub fn spend(&mut self, cost: AreaCredits) {
        self.credits_used_today += cost as u32;
        self.requests_today += 1;
    }

    pub fn remaining(&self) -> u32 {
        self.daily_credit_limit.saturating_sub(self.credits_used_today)
    }

    pub fn usage_percent(&self) -> f32 {
        (self.credits_used_today as f32 / self.daily_credit_limit as f32) * 100.0
    }
}

/// Metadata for a region we poll (bounding box).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RegionBBox {
    pub name: String,
    pub lamin: f64,
    pub lamax: f64,
    pub lomin: f64,
    pub lomax: f64,
    #[serde(default)]
    pub cost: AreaCredits,
    #[serde(with = "humantime_serde", default = "default_poll_interval")]
    pub poll_interval: Duration,
    #[serde(skip)]
    pub last_polled: Option<Instant>,
    #[serde(skip)]
    pub last_aircraft_count: usize,
    #[serde(skip)]
    pub total_polls: u64,
}

fn default_poll_interval() -> Duration {
    Duration::from_secs(30)
}

impl RegionBBox {
    pub fn new(name: &str, lamin: f64, lamax: f64, lomin: f64, lomax: f64, cost: AreaCredits, interval_secs: u64) -> Self {
        Self {
            name: name.to_string(),
            lamin,
            lamax,
            lomin,
            lomax,
            cost,
            poll_interval: Duration::from_secs(interval_secs),
            last_polled: None,
            last_aircraft_count: 0,
            total_polls: 0,
        }
    }

    pub fn time_until_next_poll(&self) -> Option<Duration> {
        self.last_polled.map(|last| {
            let elapsed = last.elapsed();
            if elapsed >= self.poll_interval {
                Duration::ZERO
            } else {
                self.poll_interval - elapsed
            }
        })
    }
}

/// The unified polling policy that determines:
/// - When a region is allowed to poll
/// - Whether we can afford to poll it based on credits
/// - Or if we fallback to internal prediction
#[derive(Debug)]
pub struct PollingPolicy {
    pub credit_mgr: CreditManager,
    pub regions: Vec<RegionBBox>,
    pub emergency_mode: bool,
}

impl PollingPolicy {
    pub fn new(daily_limit: u32, regions: Vec<RegionBBox>) -> Self {
        Self {
            credit_mgr: CreditManager::new(daily_limit),
            regions,
            emergency_mode: false,
        }
    }

    /// Decide whether to poll a region right now.
    pub fn should_poll(&mut self, region_idx: usize) -> PollDecision {
        self.credit_mgr.maybe_reset();

        let region = &self.regions[region_idx];

        // Never poll more frequently than interval
        if let Some(last) = region.last_polled {
            if last.elapsed() < region.poll_interval {
                return PollDecision::Skip;
            }
        }

        // Credit availability rules
        if !self.credit_mgr.can_spend(region.cost) {
            // Critical if credits nearly exhausted (>95%)
            if self.credit_mgr.usage_percent() >= 95.0 {
                if !self.emergency_mode {
                    self.emergency_mode = true;
                    tracing::warn!(
                        "CREDIT EMERGENCY: {}% credits used, switching to prediction-only mode",
                        self.credit_mgr.usage_percent()
                    );
                }
                return PollDecision::Critical;
            }
            return PollDecision::Skip;
        }

        // Exit emergency mode if we have credits again
        if self.emergency_mode && self.credit_mgr.usage_percent() < 90.0 {
            self.emergency_mode = false;
            tracing::info!("Exiting emergency mode, credits available again");
        }

        PollDecision::PollNow
    }

    /// Spend credits & mark region as polled.
    pub fn register_poll(&mut self, region_idx: usize, aircraft_count: usize) {
        let region = &mut self.regions[region_idx];
        self.credit_mgr.spend(region.cost);
        region.last_polled = Some(Instant::now());
        region.last_aircraft_count = aircraft_count;
        region.total_polls += 1;
    }

    /// Get next region that needs polling (most overdue first)
    pub fn next_due_region(&self) -> Option<usize> {
        let mut best_idx: Option<usize> = None;
        let mut best_overdue = Duration::ZERO;

        for (idx, region) in self.regions.iter().enumerate() {
            let overdue = match region.last_polled {
                None => Duration::from_secs(u64::MAX), // Never polled = highest priority
                Some(last) => {
                    let elapsed = last.elapsed();
                    if elapsed > region.poll_interval {
                        elapsed - region.poll_interval
                    } else {
                        continue; // Not due yet
                    }
                }
            };

            if overdue > best_overdue {
                best_overdue = overdue;
                best_idx = Some(idx);
            }
        }

        best_idx
    }

    pub fn status_summary(&self) -> PolicyStatus {
        PolicyStatus {
            credits_used: self.credit_mgr.credits_used_today,
            credits_remaining: self.credit_mgr.remaining(),
            usage_percent: self.credit_mgr.usage_percent(),
            requests_today: self.credit_mgr.requests_today,
            emergency_mode: self.emergency_mode,
            regions: self.regions.iter().map(|r| RegionStatus {
                name: r.name.clone(),
                last_aircraft_count: r.last_aircraft_count,
                total_polls: r.total_polls,
                time_until_next: r.time_until_next_poll().map(|d| d.as_secs()),
            }).collect(),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct PolicyStatus {
    pub credits_used: u32,
    pub credits_remaining: u32,
    pub usage_percent: f32,
    pub requests_today: u32,
    pub emergency_mode: bool,
    pub regions: Vec<RegionStatus>,
}

#[derive(Debug, Serialize)]
pub struct RegionStatus {
    pub name: String,
    pub last_aircraft_count: usize,
    pub total_polls: u64,
    pub time_until_next: Option<u64>,
}

/// Internal continuous propagation model for aircraft.
/// This becomes the fallback when polling is skipped.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AircraftState {
    pub icao24: String,
    pub callsign: String,
    pub lat: f64,
    pub lon: f64,
    pub alt_m: f64,
    pub velocity_ms: f64,
    pub heading_deg: f64,
    pub vertical_rate_ms: f64,
    pub last_update: DateTime<Utc>,
    pub uncertainty: f64,
    pub region: String,
    pub is_predicted: bool,
}

impl AircraftState {
    /// Propagate aircraft state forward by dt seconds using 4D kinematics
    pub fn propagate(&mut self, dt: f64) {
        // Basic 4D kinematic propagation
        let heading_rad = self.heading_deg.to_radians();
        let dx = self.velocity_ms * heading_rad.sin() * dt;
        let dy = self.velocity_ms * heading_rad.cos() * dt;
        let dalt = self.vertical_rate_ms * dt;

        // Earth projection approximation (meters to degrees)
        let lat_rad = self.lat.to_radians();
        self.lon += dx / (111_320.0 * lat_rad.cos());
        self.lat += dy / 110_540.0;
        self.alt_m += dalt;

        // Uncertainty increases linearly with time (0.02 per second = ~1.2 per minute)
        self.uncertainty = (self.uncertainty + dt * 0.02).min(1.0);
        
        self.is_predicted = true;
    }

    /// Convert to 8D vQbit representation for UUM substrate
    pub fn to_vqbit_8d(&self) -> [f64; 8] {
        let alt_ft = self.alt_m * 3.28084;
        let time_norm = ((self.last_update.timestamp() % 86400) as f64) / 86400.0;
        let alt_norm = (alt_ft / 50000.0).clamp(0.0, 1.0);
        
        // Risk assessment based on altitude and uncertainty
        let base_risk = if alt_ft < 5000.0 { 0.7 } else if alt_ft < 10000.0 { 0.5 } else { 0.3 };
        let risk = (base_risk + self.uncertainty * 0.3).min(1.0);
        
        [
            self.lon / 180.0,           // D0: Longitude normalized [-1, 1]
            self.lat / 90.0,            // D1: Latitude normalized [-1, 1]
            alt_norm,                   // D2: Altitude normalized [0, 1]
            time_norm,                  // D3: Time of day [0, 1]
            0.5,                        // D4: Intent (neutral)
            risk,                       // D5: Risk level
            1.0 - self.uncertainty,     // D6: Compliance/confidence
            self.uncertainty,           // D7: Measurement uncertainty
        ]
    }
}

/// Manages real-time aircraft prediction when OpenSky isn't polled.
#[derive(Debug)]
pub struct PredictionEngine {
    pub aircraft: HashMap<String, AircraftState>,
    pub stale_threshold_secs: i64,
}

impl PredictionEngine {
    pub fn new(stale_threshold_secs: i64) -> Self {
        Self {
            aircraft: HashMap::new(),
            stale_threshold_secs,
        }
    }

    /// Update from a fresh OpenSky measurement
    pub fn update_from_measurement(&mut self, mut ac: AircraftState) {
        ac.uncertainty = 0.0; // Reset uncertainty on fresh measurement
        ac.is_predicted = false;
        ac.last_update = Utc::now();
        self.aircraft.insert(ac.icao24.clone(), ac);
    }

    /// Propagate all aircraft by Δt seconds
    pub fn propagate_all(&mut self, dt_secs: f64) {
        for ac in self.aircraft.values_mut() {
            ac.propagate(dt_secs);
        }
    }

    /// Remove stale aircraft (not updated for too long)
    pub fn prune_stale(&mut self) {
        let now = Utc::now();
        let threshold = chrono::Duration::seconds(self.stale_threshold_secs);
        
        self.aircraft.retain(|_, ac| {
            now.signed_duration_since(ac.last_update) < threshold
        });
    }

    /// Get snapshot of all current aircraft states
    pub fn get_snapshot(&self) -> Vec<AircraftState> {
        self.aircraft.values().cloned().collect()
    }

    /// Get aircraft count
    pub fn aircraft_count(&self) -> usize {
        self.aircraft.len()
    }

    /// Get count of aircraft currently being predicted (not fresh from API)
    pub fn predicted_count(&self) -> usize {
        self.aircraft.values().filter(|ac| ac.is_predicted).count()
    }
}

// Humantime serde module for Duration serialization
mod humantime_serde {
    use serde::{self, Deserialize, Deserializer, Serializer};
    use std::time::Duration;

    pub fn serialize<S>(duration: &Duration, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_u64(duration.as_secs())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Duration, D::Error>
    where
        D: Deserializer<'de>,
    {
        let secs = u64::deserialize(deserializer)?;
        Ok(Duration::from_secs(secs))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_credit_manager() {
        let mut mgr = CreditManager::new(4000);
        assert!(mgr.can_spend(AreaCredits::Small));
        assert!(mgr.can_spend(AreaCredits::Global));
        
        mgr.spend(AreaCredits::Global);
        assert_eq!(mgr.credits_used_today, 4);
        assert_eq!(mgr.remaining(), 3996);
    }

    #[test]
    fn test_aircraft_propagation() {
        let mut ac = AircraftState {
            icao24: "TEST".into(),
            callsign: "TEST123".into(),
            lat: 40.0,
            lon: -74.0,
            alt_m: 10000.0,
            velocity_ms: 250.0,
            heading_deg: 90.0,  // East
            vertical_rate_ms: 0.0,
            last_update: Utc::now(),
            uncertainty: 0.0,
            region: "NYC".into(),
            is_predicted: false,
        };

        let initial_lon = ac.lon;
        ac.propagate(60.0); // 1 minute

        // Should have moved east
        assert!(ac.lon > initial_lon);
        assert!(ac.is_predicted);
        assert!(ac.uncertainty > 0.0);
    }

    #[test]
    fn test_vqbit_conversion() {
        let ac = AircraftState {
            icao24: "TEST".into(),
            callsign: "TEST123".into(),
            lat: 40.0,
            lon: -74.0,
            alt_m: 10000.0,
            velocity_ms: 250.0,
            heading_deg: 90.0,
            vertical_rate_ms: 0.0,
            last_update: Utc::now(),
            uncertainty: 0.1,
            region: "NYC".into(),
            is_predicted: false,
        };

        let vqbit = ac.to_vqbit_8d();
        assert_eq!(vqbit.len(), 8);
        assert!(vqbit[0] >= -1.0 && vqbit[0] <= 1.0); // D0: lon
        assert!(vqbit[1] >= -1.0 && vqbit[1] <= 1.0); // D1: lat
        assert!(vqbit[7] >= 0.0 && vqbit[7] <= 1.0);  // D7: uncertainty
    }
}

