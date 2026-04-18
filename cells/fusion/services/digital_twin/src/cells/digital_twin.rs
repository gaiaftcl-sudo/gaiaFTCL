/*!
 * cells/digital_twin.rs
 *
 * UUM 8D Digital Twin Cell
 *
 * - Every aircraft is a living entity in the substrate.
 * - Each twin maintains its own safety bubble and local "UUM-8D space".
 * - Visual state includes flight number label, true heading, and wind opacity.
 * - NO INCOMPLETE IMPLEMENTATIONS - complete production implementation.
 */

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::event_schema::*;
use crate::uum_digital_twin::UUM8D;

/// How complete an aircraft's data is.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum DataCompleteness {
    Full,     // flight plan + radar + altitude + velocity
    Partial,  // missing some key fields
    Critical, // stale or obviously inconsistent
}

/// Safety bubble around an aircraft in meters/seconds.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SafetyBubble {
    pub horizontal_radius_m: f64,
    pub vertical_radius_m: f64,
    pub time_horizon_s: f64,
    pub uncertainty_margin_m: f64,
}

/// Local UUM-8D space for an aircraft: everything it needs to decide safe/unsafe.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AircraftLocalSpace {
    /// Other aircraft inside prediction horizon.
    pub nearby_aircraft: Vec<NearbyAircraft>,
    /// True wind vector at this aircraft.
    pub wind_direction_deg_true: f64,
    pub wind_speed_kts: f64,
    /// True if no conflict and data is healthy.
    pub is_overall_safe: bool,
}

/// A nearby aircraft relative to our entity.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NearbyAircraft {
    pub other_id: String,
    pub relative_bearing_deg: f64,
    pub horizontal_distance_m: f64,
    pub vertical_separation_m: f64,
    pub is_conflict: bool,
}

/// Visual icon state for the front-end.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AircraftIcon {
    pub aircraft_id: String,
    pub flight_number: String,
    pub callsign: String,
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub altitude_m: f64,
    /// True heading (deg, 0–360, where 0/360 = North).
    pub heading_deg_true: f64,
    /// Wind direction (deg, from where the wind is coming, 0–360).
    pub wind_direction_deg_true: f64,
    /// Wind speed in knots.
    pub wind_speed_kts: f64,
    /// 0.0–1.0, higher when wind speed is higher (for opacity).
    pub wind_opacity: f32,
    /// True if this aircraft is currently evaluated as "safe in its own bubble".
    pub is_inside_own_bubble_safe: bool,
    /// True if any conflict detected with others.
    pub has_conflict: bool,
}

/// One aircraft's complete twin state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AircraftTwin {
    pub id: String,
    pub flight_number: String,
    pub callsign: String,
    pub uum8d: UUM8D,
    pub heading_deg_true: f64,
    pub ground_speed_kts: f64,
    pub wind_direction_deg_true: f64,
    pub wind_speed_kts: f64,
    pub has_flight_plan: bool,
    pub flight_plan_id: Option<String>,
    pub radar_track_id: Option<String>,
    pub data_completeness: DataCompleteness,
    pub safety_bubble: SafetyBubble,
    pub local_space: AircraftLocalSpace,
    pub last_update_time: DateTime<Utc>,
}

/// Input: raw world sample per aircraft, from core / sensors.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AircraftWorldSample {
    pub id: String,
    pub flight_number: String,
    pub callsign: String,
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub altitude_m: f64,
    pub heading_deg_true: f64,
    pub ground_speed_kts: f64,
    pub has_flight_plan: bool,
    pub flight_plan_id: Option<String>,
    pub radar_track_id: Option<String>,
    pub has_altitude: bool,
    pub has_position: bool,
    pub has_velocity: bool,
    pub global_wind_direction_deg_true: f64,
    pub global_wind_speed_kts: f64,
    pub last_update_time: DateTime<Utc>,
}

/// Output: alerts back to the substrate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SafetyAlert {
    ProximityConflict {
        a_id: String,
        b_id: String,
        horiz_dist_m: f64,
        vert_dist_m: f64,
    },
    DataIncomplete {
        aircraft_id: String,
        reason: String,
    },
}

/// The cell that owns all aircraft twins for this node.
#[derive(Debug, Default)]
pub struct DigitalTwinCell {
    aircraft: HashMap<String, AircraftTwin>,
}

impl DigitalTwinCell {
    pub fn new() -> Self {
        Self {
            aircraft: HashMap::new(),
        }
    }

    /// Ingest raw world samples (from flight plans, radar, ADS-B, etc.)
    /// and update or create aircraft twins.
    pub fn update_from_world(
        &mut self,
        samples: &[AircraftWorldSample],
    ) {
        for sample in samples {
            let data_completeness = classify_data_completeness(sample);

            let mut twin = self.aircraft.entry(sample.id.clone()).or_insert_with(|| {
                let initial_uum = UUM8D::from_lat_lon_alt(
                    sample.latitude_deg,
                    sample.longitude_deg,
                    sample.altitude_m,
                    sample.last_update_time,
                );

                AircraftTwin {
                    id: sample.id.clone(),
                    flight_number: sample.flight_number.clone(),
                    callsign: sample.callsign.clone(),
                    uum8d: initial_uum,
                    heading_deg_true: normalize_heading(sample.heading_deg_true),
                    ground_speed_kts: sample.ground_speed_kts,
                    wind_direction_deg_true: normalize_heading(
                        sample.global_wind_direction_deg_true,
                    ),
                    wind_speed_kts: sample.global_wind_speed_kts,
                    has_flight_plan: sample.has_flight_plan,
                    flight_plan_id: sample.flight_plan_id.clone(),
                    radar_track_id: sample.radar_track_id.clone(),
                    data_completeness,
                    safety_bubble: SafetyBubble {
                        horizontal_radius_m: 0.0,
                        vertical_radius_m: 0.0,
                        time_horizon_s: 0.0,
                        uncertainty_margin_m: 0.0,
                    },
                    local_space: AircraftLocalSpace {
                        nearby_aircraft: Vec::new(),
                        wind_direction_deg_true: normalize_heading(
                            sample.global_wind_direction_deg_true,
                        ),
                        wind_speed_kts: sample.global_wind_speed_kts,
                        is_overall_safe: true,
                    },
                    last_update_time: sample.last_update_time,
                }
            });

            // Update core kinematics & metadata.
            twin.flight_number = sample.flight_number.clone();
            twin.callsign = sample.callsign.clone();
            twin.heading_deg_true = normalize_heading(sample.heading_deg_true);
            twin.ground_speed_kts = sample.ground_speed_kts;
            twin.wind_direction_deg_true =
                normalize_heading(sample.global_wind_direction_deg_true);
            twin.wind_speed_kts = sample.global_wind_speed_kts;
            twin.has_flight_plan = sample.has_flight_plan;
            twin.flight_plan_id = sample.flight_plan_id.clone();
            twin.radar_track_id = sample.radar_track_id.clone();
            twin.data_completeness = data_completeness;
            twin.last_update_time = sample.last_update_time;

            // Update UUM-8D coordinates from physical location/time.
            twin.uum8d.update_from_lat_lon_alt(
                sample.latitude_deg,
                sample.longitude_deg,
                sample.altitude_m,
                sample.last_update_time,
                twin.heading_deg_true,
            );
        }
    }

    /// Step the cell: recompute safety bubbles, local spaces, and emit alerts.
    pub fn step(&mut self, now: DateTime<Utc>) -> Vec<SafetyAlert> {
        let mut alerts = Vec::new();

        // Mark stale twins and update safety bubbles.
        for twin in self.aircraft.values_mut() {
            let age_s = (now - twin.last_update_time).num_seconds();
            if age_s > 10 {
                twin.data_completeness = DataCompleteness::Critical;
            }

            update_safety_bubble(twin);

            // Clear previous local space; will be rebuilt below.
            twin.local_space.nearby_aircraft.clear();
            twin.local_space.wind_direction_deg_true = twin.wind_direction_deg_true;
            twin.local_space.wind_speed_kts = twin.wind_speed_kts;
            twin.local_space.is_overall_safe = true;
        }

        // Pairwise conflict checks and local space construction.
        let ids: Vec<String> = self.aircraft.keys().cloned().collect();
        for i in 0..ids.len() {
            for j in (i + 1)..ids.len() {
                let (a_id, b_id) = (&ids[i], &ids[j]);
                let (a_clone, b_clone) = {
                    let a = self.aircraft.get(a_id).cloned();
                    let b = self.aircraft.get(b_id).cloned();
                    if let (Some(a), Some(b)) = (a, b) {
                        (a, b)
                    } else {
                        continue;
                    }
                };

                let (horiz_dist, vert_dist) =
                    distance_between(&a_clone.uum8d, &b_clone.uum8d);

                let conflict_a = is_inside_conflict(
                    horiz_dist,
                    vert_dist,
                    &a_clone.safety_bubble,
                );
                let conflict_b = is_inside_conflict(
                    horiz_dist,
                    vert_dist,
                    &b_clone.safety_bubble,
                );

                // Relative bearings for each side.
                let bearing_a_to_b =
                    bearing_between(&a_clone.uum8d, &b_clone.uum8d);
                let bearing_b_to_a =
                    bearing_between(&b_clone.uum8d, &a_clone.uum8d);

                {
                    let a_mut = self.aircraft.get_mut(a_id).unwrap();
                    a_mut.local_space.nearby_aircraft.push(NearbyAircraft {
                        other_id: b_id.clone(),
                        relative_bearing_deg: bearing_a_to_b,
                        horizontal_distance_m: horiz_dist,
                        vertical_separation_m: vert_dist,
                        is_conflict: conflict_a,
                    });
                    if conflict_a {
                        a_mut.local_space.is_overall_safe = false;
                    }
                }

                {
                    let b_mut = self.aircraft.get_mut(b_id).unwrap();
                    b_mut.local_space.nearby_aircraft.push(NearbyAircraft {
                        other_id: a_id.clone(),
                        relative_bearing_deg: bearing_b_to_a,
                        horizontal_distance_m: horiz_dist,
                        vertical_separation_m: vert_dist,
                        is_conflict: conflict_b,
                    });
                    if conflict_b {
                        b_mut.local_space.is_overall_safe = false;
                    }
                }

                if conflict_a || conflict_b {
                    alerts.push(SafetyAlert::ProximityConflict {
                        a_id: a_id.clone(),
                        b_id: b_id.clone(),
                        horiz_dist_m: horiz_dist,
                        vert_dist_m: vert_dist,
                    });
                }
            }
        }

        // Data-incomplete alerts.
        for twin in self.aircraft.values() {
            if twin.data_completeness == DataCompleteness::Critical {
                alerts.push(SafetyAlert::DataIncomplete {
                    aircraft_id: twin.id.clone(),
                    reason: "Critical or stale data for active aircraft".to_string(),
                });
            }
        }

        alerts
    }

    /// Export icon states for UI: each aircraft gets a full, self-contained description.
    pub fn export_icons(&self) -> Vec<AircraftIcon> {
        self.aircraft
            .values()
            .map(|twin| {
                let wind_opacity = compute_wind_opacity(twin.wind_speed_kts);

                let has_conflict = twin
                    .local_space
                    .nearby_aircraft
                    .iter()
                    .any(|n| n.is_conflict);

                AircraftIcon {
                    aircraft_id: twin.id.clone(),
                    flight_number: twin.flight_number.clone(),
                    callsign: twin.callsign.clone(),
                    latitude_deg: twin.uum8d.lat_deg(),
                    longitude_deg: twin.uum8d.lon_deg(),
                    altitude_m: twin.uum8d.alt_m(),
                    heading_deg_true: twin.heading_deg_true,
                    wind_direction_deg_true: twin.wind_direction_deg_true,
                    wind_speed_kts: twin.wind_speed_kts,
                    wind_opacity,
                    is_inside_own_bubble_safe: twin.local_space.is_overall_safe
                        && twin.data_completeness != DataCompleteness::Critical,
                    has_conflict,
                }
            })
            .collect()
    }

    /// Get count of tracked aircraft
    pub fn aircraft_count(&self) -> usize {
        self.aircraft.len()
    }

    /// Get all safety alerts
    pub fn get_alerts(&self) -> Vec<SafetyAlert> {
        let mut alerts = Vec::new();
        
        for twin in self.aircraft.values() {
            if twin.data_completeness == DataCompleteness::Critical {
                alerts.push(SafetyAlert::DataIncomplete {
                    aircraft_id: twin.id.clone(),
                    reason: "Critical data completeness".to_string(),
                });
            }
            
            for nearby in &twin.local_space.nearby_aircraft {
                if nearby.is_conflict {
                    alerts.push(SafetyAlert::ProximityConflict {
                        a_id: twin.id.clone(),
                        b_id: nearby.other_id.clone(),
                        horiz_dist_m: nearby.horizontal_distance_m,
                        vert_dist_m: nearby.vertical_separation_m,
                    });
                }
            }
        }
        
        alerts
    }
}

/// Decide how complete data is, based on sample flags.
fn classify_data_completeness(sample: &AircraftWorldSample) -> DataCompleteness {
    let mut missing = 0;
    if !sample.has_position {
        missing += 1;
    }
    if !sample.has_altitude {
        missing += 1;
    }
    if !sample.has_velocity {
        missing += 1;
    }

    match missing {
        0 => DataCompleteness::Full,
        1 => DataCompleteness::Partial,
        _ => DataCompleteness::Partial,
    }
}

/// Update safety bubble + risk/uncertainty in UUM-8D.
fn update_safety_bubble(twin: &mut AircraftTwin) {
    // Base minima (configurable per flight rules).
    let base_horiz = 9260.0; // ~5 NM in meters
    let base_vert = 300.0;   // ~1000 ft in meters

    let uncertainty_factor = match twin.data_completeness {
        DataCompleteness::Full => 1.0,
        DataCompleteness::Partial => 1.5,
        DataCompleteness::Critical => 2.0,
    };

    twin.safety_bubble.horizontal_radius_m = base_horiz * uncertainty_factor;
    twin.safety_bubble.vertical_radius_m = base_vert * uncertainty_factor;
    twin.safety_bubble.time_horizon_s = 120.0; // 2 min lookahead
    twin.safety_bubble.uncertainty_margin_m =
        base_horiz * (uncertainty_factor - 1.0);

    twin.uum8d.d5_risk = (uncertainty_factor - 1.0).max(0.0);
    twin.uum8d.d7_uncert = match twin.data_completeness {
        DataCompleteness::Full => 0.1,
        DataCompleteness::Partial => 0.5,
        DataCompleteness::Critical => 0.9,
    };
}

/// Compute distance between two UUM8D states.
fn distance_between(a: &UUM8D, b: &UUM8D) -> (f64, f64) {
    let lat1 = a.lat_deg().to_radians();
    let lon1 = a.lon_deg().to_radians();
    let lat2 = b.lat_deg().to_radians();
    let lon2 = b.lon_deg().to_radians();

    let dlat = lat2 - lat1;
    let dlon = lon2 - lon1;

    let sin_dlat = (dlat / 2.0).sin();
    let sin_dlon = (dlon / 2.0).sin();

    let a_hav = sin_dlat * sin_dlat
        + lat1.cos() * lat2.cos() * sin_dlon * sin_dlon;

    let c = 2.0 * a_hav.sqrt().atan2((1.0 - a_hav).sqrt());
    let earth_radius_m = 6_371_000.0;

    let horiz_dist = earth_radius_m * c;
    let vert_dist = (a.alt_m() - b.alt_m()).abs();

    (horiz_dist, vert_dist)
}

/// Check if current distance violates someone's safety bubble.
fn is_inside_conflict(
    horiz_dist_m: f64,
    vert_dist_m: f64,
    bubble: &SafetyBubble,
) -> bool {
    horiz_dist_m < bubble.horizontal_radius_m
        && vert_dist_m < bubble.vertical_radius_m
}

/// Bearing from A to B in degrees (0–360, true).
fn bearing_between(a: &UUM8D, b: &UUM8D) -> f64 {
    let lat1 = a.lat_deg().to_radians();
    let lon1 = a.lon_deg().to_radians();
    let lat2 = b.lat_deg().to_radians();
    let lon2 = b.lon_deg().to_radians();

    let dlon = lon2 - lon1;

    let y = dlon.sin() * lat2.cos();
    let x = lat1.cos() * lat2.sin()
        - lat1.sin() * lat2.cos() * dlon.cos();

    let bearing_rad = y.atan2(x);
    normalize_heading(bearing_rad.to_degrees())
}

/// Normalize heading to 0–360 degrees.
fn normalize_heading(mut deg: f64) -> f64 {
    while deg < 0.0 {
        deg += 360.0;
    }
    while deg >= 360.0 {
        deg -= 360.0;
    }
    deg
}

/// Convert wind speed into an opacity for UI (0.0–1.0).
fn compute_wind_opacity(wind_speed_kts: f64) -> f32 {
    // 0–60 kts scaled to 0.1–1.0, clamped.
    let max_speed = 60.0;
    let clamped = wind_speed_kts.max(0.0).min(max_speed);
    let normalized = clamped / max_speed;
    let opacity = 0.1 + 0.9 * normalized;
    opacity as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_heading() {
        assert_eq!(normalize_heading(0.0), 0.0);
        assert_eq!(normalize_heading(360.0), 0.0);
        assert_eq!(normalize_heading(370.0), 10.0);
        assert_eq!(normalize_heading(-10.0), 350.0);
    }

    #[test]
    fn test_wind_opacity() {
        assert!((compute_wind_opacity(0.0) - 0.1).abs() < 0.01);
        assert!((compute_wind_opacity(30.0) - 0.55).abs() < 0.01);
        assert!((compute_wind_opacity(60.0) - 1.0).abs() < 0.01);
        assert!((compute_wind_opacity(100.0) - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_digital_twin_creation() {
        let mut cell = DigitalTwinCell::new();
        assert_eq!(cell.aircraft_count(), 0);

        let sample = AircraftWorldSample {
            id: "AAL123".to_string(),
            flight_number: "AA123".to_string(),
            callsign: "AMERICAN 123".to_string(),
            latitude_deg: 40.6413,
            longitude_deg: -73.7781,
            altitude_m: 10668.0, // 35,000ft
            heading_deg_true: 90.0,
            ground_speed_kts: 485.0,
            has_flight_plan: true,
            flight_plan_id: Some("FP123".to_string()),
            radar_track_id: Some("TRK123".to_string()),
            has_altitude: true,
            has_position: true,
            has_velocity: true,
            global_wind_direction_deg_true: 270.0,
            global_wind_speed_kts: 85.0,
            last_update_time: Utc::now(),
        };

        cell.update_from_world(&[sample]);
        assert_eq!(cell.aircraft_count(), 1);

        let icons = cell.export_icons();
        assert_eq!(icons.len(), 1);
        assert_eq!(icons[0].callsign, "AMERICAN 123");
    }
}
