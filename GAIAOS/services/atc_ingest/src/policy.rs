//! Credit manager + regional polling + prediction engine + aircraft model.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::time::{Duration, Instant};

/// Credits consumed per /states/all call by bounding box size.
#[derive(Clone, Copy, Debug, Default)]
pub enum AreaCredits {
    #[default]
    Small = 1,   // <500x500km
    Medium = 2,  // <1000x1000km
    Large = 3,   // <2000x2000km
    Global = 4,  // full globe
}

/// Polling decision classification for each region.
#[derive(Clone, Debug, PartialEq)]
pub enum PollDecision {
    PollNow,
    Skip,
    Critical,
}

/// Tracks daily API credit usage.
#[derive(Debug, Clone)]
pub struct CreditManager {
    pub daily_credit_limit: u32,
    pub credits_used_today: u32,
    pub next_reset_at: DateTime<Utc>,
}

impl CreditManager {
    pub fn new(limit: u32) -> Self {
        Self {
            daily_credit_limit: limit,
            credits_used_today: 0,
            next_reset_at: Utc::now() + chrono::Duration::hours(24),
        }
    }

    pub fn maybe_reset(&mut self) {
        let now = Utc::now();
        if now >= self.next_reset_at {
            log::info!(
                "Credit reset: {} credits used yesterday",
                self.credits_used_today
            );
            self.credits_used_today = 0;
            self.next_reset_at = now + chrono::Duration::hours(24);
        }
    }

    pub fn can_spend(&self, cost: AreaCredits) -> bool {
        self.credits_used_today + cost as u32 <= self.daily_credit_limit
    }

    pub fn spend(&mut self, cost: AreaCredits) {
        self.credits_used_today += cost as u32;
    }

    pub fn remaining(&self) -> u32 {
        self.daily_credit_limit.saturating_sub(self.credits_used_today)
    }
}

/// Bounding box for region polling.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RegionBBox {
    pub name: String,
    pub lamin: f64,
    pub lamax: f64,
    pub lomin: f64,
    pub lomax: f64,
    #[serde(skip)]
    pub cost: AreaCredits,
    #[serde(skip)]
    pub poll_interval: Duration,
    #[serde(skip)]
    pub last_polled: Option<Instant>,
}

impl RegionBBox {
    pub fn new(
        name: &str,
        lamin: f64,
        lamax: f64,
        lomin: f64,
        lomax: f64,
        cost: AreaCredits,
        interval_secs: u64,
    ) -> Self {
        Self {
            name: name.to_string(),
            lamin,
            lamax,
            lomin,
            lomax,
            cost,
            poll_interval: Duration::from_secs(interval_secs),
            last_polled: None,
        }
    }
}

/// Unified polling policy for OpenSky.
#[derive(Debug)]
pub struct PollingPolicy {
    pub credit_mgr: CreditManager,
    pub regions: Vec<RegionBBox>,
}

impl PollingPolicy {
    pub fn new(daily_limit: u32, regions: Vec<RegionBBox>) -> Self {
        Self {
            credit_mgr: CreditManager::new(daily_limit),
            regions,
        }
    }

    pub fn should_poll(&mut self, region: &RegionBBox) -> PollDecision {
        self.credit_mgr.maybe_reset();

        if let Some(last) = region.last_polled {
            if last.elapsed() < region.poll_interval {
                return PollDecision::Skip;
            }
        }

        if !self.credit_mgr.can_spend(region.cost) {
            if self.credit_mgr.credits_used_today as f32
                >= (self.credit_mgr.daily_credit_limit as f32 * 0.95)
            {
                return PollDecision::Critical;
            }
            return PollDecision::Skip;
        }

        PollDecision::PollNow
    }

    pub fn should_poll_by_index(&mut self, idx: usize) -> PollDecision {
        self.credit_mgr.maybe_reset();

        let region = &self.regions[idx];
        if let Some(last) = region.last_polled {
            if last.elapsed() < region.poll_interval {
                return PollDecision::Skip;
            }
        }

        if !self.credit_mgr.can_spend(region.cost) {
            if self.credit_mgr.credits_used_today as f32
                >= (self.credit_mgr.daily_credit_limit as f32 * 0.95)
            {
                return PollDecision::Critical;
            }
            return PollDecision::Skip;
        }

        PollDecision::PollNow
    }

    pub fn register_poll(&mut self, region: &mut RegionBBox) {
        self.credit_mgr.spend(region.cost);
        region.last_polled = Some(Instant::now());
    }

    pub fn register_poll_by_index(&mut self, idx: usize) {
        let cost = self.regions[idx].cost;
        self.credit_mgr.spend(cost);
        self.regions[idx].last_polled = Some(Instant::now());
    }
}

/// Internal real-time aircraft state used for propagation.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AircraftState {
    pub icao24: String,
    pub callsign: String,
    pub origin_country: String,
    pub lat: f64,
    pub lon: f64,
    pub alt_m: f64,
    pub velocity_ms: f64,
    pub heading_deg: f64,
    pub vertical_rate_ms: f64,
    pub last_update: DateTime<Utc>,
    pub uncertainty: f64,
    pub category: Option<i64>,
}

impl AircraftState {
    pub fn propagate(&mut self, dt: f64) {
        let heading_rad = self.heading_deg.to_radians();
        let dx = self.velocity_ms * heading_rad.sin() * dt;
        let dy = self.velocity_ms * heading_rad.cos() * dt;
        let dalt = self.vertical_rate_ms * dt;

        // rough Earth approximation (good enough for short dt)
        if self.lat.abs() < 89.0 {
            self.lon += dx / (111_320.0 * self.lat.to_radians().cos());
        }
        self.lat += dy / 110_540.0;
        self.alt_m += dalt;

        self.uncertainty += dt * 0.02; // uncertainty grows with time
    }
}

/// Runs prediction when we are not sampling OpenSky.
#[derive(Debug, Default)]
pub struct PredictionEngine {
    pub aircraft: HashMap<String, AircraftState>,
}

impl PredictionEngine {
    pub fn new() -> Self {
        Self {
            aircraft: HashMap::new(),
        }
    }

    pub fn update_from_measurement(&mut self, mut ac: AircraftState) {
        ac.uncertainty = 0.0; // Reset uncertainty on fresh measurement
        self.aircraft.insert(ac.icao24.clone(), ac);
    }

    pub fn propagate_all(&mut self, dt_secs: f64) {
        for ac in self.aircraft.values_mut() {
            ac.propagate(dt_secs);
        }
    }

    pub fn prune_stale(&mut self, max_age_secs: i64) {
        let now = Utc::now();
        self.aircraft.retain(|_, ac| {
            now.signed_duration_since(ac.last_update).num_seconds() < max_age_secs
        });
    }

    pub fn get_snapshot(&self) -> Vec<AircraftState> {
        self.aircraft.values().cloned().collect()
    }

    pub fn count(&self) -> usize {
        self.aircraft.len()
    }
}

