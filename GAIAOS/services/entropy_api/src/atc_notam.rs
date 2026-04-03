//! ATC NOTAM generation for turbulence alerts.
//!
//! Produces NOTAM-style messages for moderate+ severity turbulence zones
//! with deterministic IDs and standard aviation formatting.

use chrono::Utc;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurbulenceAlert {
    pub location: Location,
    pub altitude_m: f64,
    pub flight_level: u32,
    pub severity: String,
    pub probability: f64,
    pub valid_time: i64,
    pub expires_time: i64,
    pub richardson_number: f64,
    pub eddy_dissipation_rate: f64,
    pub wind_shear: f64,
    pub affected_routes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Location {
    pub lat: f64,
    pub lon: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurbulenceNOTAM {
    pub notam_id: String,
    pub issued: i64,
    pub valid_from: i64,
    pub valid_until: i64,
    pub location: String,
    pub flight_levels: String,
    pub severity: String,
    pub message: String,
}

fn format_timestamp(ts: i64) -> String {
    let dt = chrono::DateTime::from_timestamp(ts, 0).unwrap_or_else(|| Utc::now());
    dt.format("%d%H%M").to_string()
}

pub fn generate_turbulence_notam(alert: &TurbulenceAlert) -> TurbulenceNOTAM {
    let now = Utc::now();
    let notam_id = format!(
        "TURB{}{}",
        now.format("%y%m%d"),
        (now.timestamp() % 10000).abs()
    );

    let lat_dir = if alert.location.lat >= 0.0 { "N" } else { "S" };
    let lon_dir = if alert.location.lon >= 0.0 { "E" } else { "W" };
    let location_desc = format!(
        "{:.1}{} {:.1}{} RADIUS 50NM",
        alert.location.lat.abs(),
        lat_dir,
        alert.location.lon.abs(),
        lon_dir
    );

    let fl_desc = format!("FL{:03}", alert.flight_level);

    let message = format!(
        "TURBULENCE FORECAST {} {} PSN {} FCST {} UTC TO {} UTC. \
         SEV {} PROB {:.0}%. EDR {:.2}. AVOID OR REQUEST ALT CHANGE.",
        notam_id,
        fl_desc,
        location_desc,
        format_timestamp(alert.valid_time),
        format_timestamp(alert.expires_time),
        alert.severity.to_uppercase(),
        alert.probability * 100.0,
        alert.eddy_dissipation_rate,
    );

    TurbulenceNOTAM {
        notam_id,
        issued: now.timestamp(),
        valid_from: alert.valid_time,
        valid_until: alert.expires_time,
        location: location_desc,
        flight_levels: fl_desc,
        severity: alert.severity.clone(),
        message,
    }
}

pub fn publish_notams(alerts: &[TurbulenceAlert]) -> Vec<TurbulenceNOTAM> {
    let mut notams = Vec::new();

    for alert in alerts {
        // Only NOTAM for moderate+ severity and high probability
        if alert.probability > 0.7
            && !matches!(alert.severity.as_str(), "None" | "Light")
        {
            let notam = generate_turbulence_notam(alert);
            notams.push(notam);
        }
    }

    notams
}

