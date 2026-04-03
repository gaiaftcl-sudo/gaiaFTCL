use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use serde::Serialize;

use gaiaos_substrate::noise::isotropic_entanglement::{IsotropicEntanglementGenerator, NoiseContext};
use franklin_guardian::oversight::stochastic::{FranklinStochasticOversight, FranklinStochasticOversightConfig};
use uum8d::{ConstitutionalOversight, QState8};

/// One trajectory point (lat/lon in degrees, alt in feet).
#[derive(Debug, Clone, Serialize)]
pub struct TrajectoryPoint {
    pub t_sec: u64,
    pub lat: f64,
    pub lon: f64,
    pub alt_ft: f64,
}

/// Mean trajectory + envelope bounds at each time sample.
#[derive(Debug, Clone, Serialize)]
pub struct TrajectorySummary {
    pub dt_sec: u64,
    pub points_mean: Vec<TrajectoryPoint>,
    pub points_min: Vec<TrajectoryPoint>,
    pub points_max: Vec<TrajectoryPoint>,
}

/// Full ensemble (stored optionally if desired).
#[derive(Debug, Clone, Serialize)]
pub struct StochasticTrajectoryEnsemble {
    pub ensemble_size: usize,
    pub horizon_sec: u64,
    pub dt_sec: u64,
    pub mean: TrajectorySummary,
}

#[derive(Debug, Clone, Serialize)]
pub struct PairSeparationMetrics {
    /// Fraction of ensemble members that violate separation minima at any time within horizon.
    pub los_probability: f64,
    /// True if any member violates separation minima at any time.
    pub los_any_member: bool,
    /// Earliest time (seconds) at which any member violates minima.
    pub earliest_los_sec: Option<u64>,
    /// Worst-case minimum horizontal separation across all members/time (nautical miles).
    pub min_horizontal_nm: f64,
    /// Worst-case minimum vertical separation across all members/time (feet).
    pub min_vertical_ft: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct CoupledPairEnsemble {
    pub ensemble_size: usize,
    pub horizon_sec: u64,
    pub dt_sec: u64,
    pub a: TrajectorySummary,
    pub b: TrajectorySummary,
    pub separation: PairSeparationMetrics,
}

/// Minimal aircraft state needed for kinematic trajectory rollout.
#[derive(Debug, Clone)]
pub struct AircraftKinematics {
    pub icao24: String,
    pub callsign: String,
    pub lat: f64,
    pub lon: f64,
    pub alt_ft: f64,
    pub velocity_kts: f64,
    pub heading_deg: f64,
    pub vertical_rate_fpm: f64,
}

/// Deterministic stochastic trajectory predictor:
/// - uses isotropic entanglement noise (64 channels) to perturb heading/speed/vertical rate
/// - enforces Franklin oversight on the noise-derived QState entropy (prevents collapse)
pub fn predict_stochastic_trajectory(
    state: &AircraftKinematics,
    ts: DateTime<Utc>,
    horizon_sec: u64,
    dt_sec: u64,
) -> Result<StochasticTrajectoryEnsemble> {
    if dt_sec == 0 {
        return Err(anyhow!("dt_sec must be > 0"));
    }
    if horizon_sec == 0 {
        return Err(anyhow!("horizon_sec must be > 0"));
    }
    if horizon_sec % dt_sec != 0 {
        return Err(anyhow!("horizon_sec must be divisible by dt_sec"));
    }

    let ensemble_size = 50usize;
    let steps = (horizon_sec / dt_sec) as usize;

    let injector = IsotropicEntanglementGenerator::new();
    let oversight = FranklinStochasticOversight::new(FranklinStochasticOversightConfig {
        // Trajectory noise should remain distributional; enforce a strong entropy floor.
        min_entropy_nats: 1.2,
        normalization_epsilon: 1e-3,
    });

    let seed_material = seed_from_aircraft(state, ts);

    // Buffers: [time_idx][member_idx]
    let mut lats = vec![vec![0.0f64; ensemble_size]; steps + 1];
    let mut lons = vec![vec![0.0f64; ensemble_size]; steps + 1];
    let mut alts = vec![vec![0.0f64; ensemble_size]; steps + 1];

    for m in 0..ensemble_size {
        lats[0][m] = state.lat;
        lons[0][m] = state.lon;
        alts[0][m] = state.alt_ft;
    }

    for t in 0..steps {
        let ctx = NoiseContext {
            epoch: (ts.timestamp() as u32) ^ 0xA11CE_u32,
            step: t as u64,
            provenance: provenance_bytes(state, ts, t),
        };

        let noise = injector.generate_from_seed_material(&seed_material, ctx)?;

        // Use Franklin oversight on a QState derived from the *distributional noise* at this step.
        // This gates against variance/entropy collapse in the injected noise itself.
        let q = qstate_from_noise(&noise);
        if t % 10 == 0 {
            oversight.validate_state(&q, t)?;
        }

        for m in 0..ensemble_size {
            let channel = m % 64;
            let n = noise.channels[channel];

            // Map isotropic 8D noise -> perturbations.
            // We keep magnitudes bounded and dimension-symmetric.
            let heading_delta_deg = (n[0] as f64) * 2.0; // +/- ~2 degrees
            let speed_delta_kts = (n[1] as f64) * 5.0;   // +/- ~5 knots
            let vrt_delta_fpm = (n[2] as f64) * 50.0;    // +/- ~50 fpm

            let heading = (state.heading_deg as f64 + heading_delta_deg).rem_euclid(360.0);
            let speed_kts = (state.velocity_kts as f64 + speed_delta_kts).max(0.0);
            let vrt_fpm = state.vertical_rate_fpm as f64 + vrt_delta_fpm;

            let (lat_next, lon_next) = step_lat_lon(
                lats[t][m],
                lons[t][m],
                heading,
                speed_kts,
                dt_sec,
            );
            let alt_next = alts[t][m] + vrt_fpm * (dt_sec as f64 / 60.0);

            lats[t + 1][m] = lat_next;
            lons[t + 1][m] = lon_next;
            alts[t + 1][m] = alt_next;
        }
    }

    let (mean, minp, maxp) = summarize(steps, dt_sec, &lats, &lons, &alts);

    Ok(StochasticTrajectoryEnsemble {
        ensemble_size,
        horizon_sec,
        dt_sec,
        mean: TrajectorySummary {
            dt_sec,
            points_mean: mean,
            points_min: minp,
            points_max: maxp,
        },
    })
}

/// Coupled stochastic predictor for an aircraft pair.
///
/// This generates per-member trajectories for both aircraft using a shared
/// entanglement noise field derived from the *pair* seed material, ensuring
/// member alignment between A and B so separation probabilities are meaningful
/// without an expensive 50×50 cross-product.
pub fn predict_coupled_pair_trajectory(
    a: &AircraftKinematics,
    b: &AircraftKinematics,
    ts: DateTime<Utc>,
    horizon_sec: u64,
    dt_sec: u64,
) -> Result<CoupledPairEnsemble> {
    if dt_sec == 0 {
        return Err(anyhow!("dt_sec must be > 0"));
    }
    if horizon_sec == 0 {
        return Err(anyhow!("horizon_sec must be > 0"));
    }
    if horizon_sec % dt_sec != 0 {
        return Err(anyhow!("horizon_sec must be divisible by dt_sec"));
    }

    let ensemble_size = 50usize;
    let steps = (horizon_sec / dt_sec) as usize;

    let injector = IsotropicEntanglementGenerator::new();
    let oversight = FranklinStochasticOversight::new(FranklinStochasticOversightConfig::default());

    let seed_material = seed_from_aircraft_pair(a, b, ts);

    let mut lats_a = vec![vec![0.0f64; ensemble_size]; steps + 1];
    let mut lons_a = vec![vec![0.0f64; ensemble_size]; steps + 1];
    let mut alts_a = vec![vec![0.0f64; ensemble_size]; steps + 1];

    let mut lats_b = vec![vec![0.0f64; ensemble_size]; steps + 1];
    let mut lons_b = vec![vec![0.0f64; ensemble_size]; steps + 1];
    let mut alts_b = vec![vec![0.0f64; ensemble_size]; steps + 1];

    for m in 0..ensemble_size {
        lats_a[0][m] = a.lat;
        lons_a[0][m] = a.lon;
        alts_a[0][m] = a.alt_ft;

        lats_b[0][m] = b.lat;
        lons_b[0][m] = b.lon;
        alts_b[0][m] = b.alt_ft;
    }

    for t in 0..steps {
        let ctx = NoiseContext {
            epoch: (ts.timestamp() as u32) ^ 0xC0D3_1E_u32,
            step: t as u64,
            provenance: pair_provenance_bytes(a, b, ts, t),
        };

        let noise = injector.generate_from_seed_material(&seed_material, ctx)?;
        let q = qstate_from_noise(&noise);
        if t % 10 == 0 {
            oversight.validate_state(&q, t)?;
        }

        for m in 0..ensemble_size {
            let channel = m % 64;
            let n = noise.channels[channel];

            // Aircraft-specific, symmetric mapping: same noise dims, different signs
            // to keep pair covariance structured but non-identical.
            let (ha, sa, va) = noise_to_perturbations(n, 1.0);
            let (hb, sb, vb) = noise_to_perturbations(n, -1.0);

            let heading_a = (a.heading_deg as f64 + ha).rem_euclid(360.0);
            let speed_a = (a.velocity_kts as f64 + sa).max(0.0);
            let vrt_a = a.vertical_rate_fpm as f64 + va;

            let heading_b = (b.heading_deg as f64 + hb).rem_euclid(360.0);
            let speed_b = (b.velocity_kts as f64 + sb).max(0.0);
            let vrt_b = b.vertical_rate_fpm as f64 + vb;

            let (lat_a_next, lon_a_next) = step_lat_lon(lats_a[t][m], lons_a[t][m], heading_a, speed_a, dt_sec);
            let (lat_b_next, lon_b_next) = step_lat_lon(lats_b[t][m], lons_b[t][m], heading_b, speed_b, dt_sec);

            let alt_a_next = alts_a[t][m] + vrt_a * (dt_sec as f64 / 60.0);
            let alt_b_next = alts_b[t][m] + vrt_b * (dt_sec as f64 / 60.0);

            lats_a[t + 1][m] = lat_a_next;
            lons_a[t + 1][m] = lon_a_next;
            alts_a[t + 1][m] = alt_a_next;

            lats_b[t + 1][m] = lat_b_next;
            lons_b[t + 1][m] = lon_b_next;
            alts_b[t + 1][m] = alt_b_next;
        }
    }

    let (mean_a, min_a, max_a) = summarize(steps, dt_sec, &lats_a, &lons_a, &alts_a);
    let (mean_b, min_b, max_b) = summarize(steps, dt_sec, &lats_b, &lons_b, &alts_b);

    let separation = compute_separation_metrics(steps, dt_sec, &lats_a, &lons_a, &alts_a, &lats_b, &lons_b, &alts_b);

    Ok(CoupledPairEnsemble {
        ensemble_size,
        horizon_sec,
        dt_sec,
        a: TrajectorySummary { dt_sec, points_mean: mean_a, points_min: min_a, points_max: max_a },
        b: TrajectorySummary { dt_sec, points_mean: mean_b, points_min: min_b, points_max: max_b },
        separation,
    })
}

fn step_lat_lon(lat: f64, lon: f64, heading_deg: f64, speed_kts: f64, dt_sec: u64) -> (f64, f64) {
    // Dead-reckoning in nautical miles.
    let dt_hours = dt_sec as f64 / 3600.0;
    let dist_nm = speed_kts * dt_hours;

    let hdg = heading_deg.to_radians();
    let dx_east_nm = dist_nm * hdg.sin();
    let dy_north_nm = dist_nm * hdg.cos();

    let dlat_deg = dy_north_nm / 60.0;
    let cos_lat = lat.to_radians().cos().max(1e-6);
    let dlon_deg = dx_east_nm / (60.0 * cos_lat);

    (lat + dlat_deg, lon + dlon_deg)
}

fn summarize(
    steps: usize,
    dt_sec: u64,
    lats: &[Vec<f64>],
    lons: &[Vec<f64>],
    alts: &[Vec<f64>],
) -> (Vec<TrajectoryPoint>, Vec<TrajectoryPoint>, Vec<TrajectoryPoint>) {
    let ensemble_size = lats[0].len();

    let mut mean = Vec::with_capacity(steps + 1);
    let mut minp = Vec::with_capacity(steps + 1);
    let mut maxp = Vec::with_capacity(steps + 1);

    for t in 0..=steps {
        let mut lat_sum = 0.0f64;
        let mut lon_sum = 0.0f64;
        let mut alt_sum = 0.0f64;

        let mut lat_min = f64::INFINITY;
        let mut lon_min = f64::INFINITY;
        let mut alt_min = f64::INFINITY;

        let mut lat_max = f64::NEG_INFINITY;
        let mut lon_max = f64::NEG_INFINITY;
        let mut alt_max = f64::NEG_INFINITY;

        for m in 0..ensemble_size {
            let lat = lats[t][m];
            let lon = lons[t][m];
            let alt = alts[t][m];
            lat_sum += lat;
            lon_sum += lon;
            alt_sum += alt;
            lat_min = lat_min.min(lat);
            lon_min = lon_min.min(lon);
            alt_min = alt_min.min(alt);
            lat_max = lat_max.max(lat);
            lon_max = lon_max.max(lon);
            alt_max = alt_max.max(alt);
        }

        let inv = 1.0 / (ensemble_size as f64);
        let t_sec = (t as u64) * dt_sec;

        mean.push(TrajectoryPoint { t_sec, lat: lat_sum * inv, lon: lon_sum * inv, alt_ft: alt_sum * inv });
        minp.push(TrajectoryPoint { t_sec, lat: lat_min, lon: lon_min, alt_ft: alt_min });
        maxp.push(TrajectoryPoint { t_sec, lat: lat_max, lon: lon_max, alt_ft: alt_max });
    }

    (mean, minp, maxp)
}

fn noise_to_perturbations(n: [f32; 8], polarity: f64) -> (f64, f64, f64) {
    let heading_delta_deg = (n[0] as f64) * 2.0 * polarity; // +/- ~2 degrees
    let speed_delta_kts = (n[1] as f64) * 5.0 * polarity;   // +/- ~5 knots
    let vrt_delta_fpm = (n[2] as f64) * 50.0 * polarity;    // +/- ~50 fpm
    (heading_delta_deg, speed_delta_kts, vrt_delta_fpm)
}

fn seed_from_aircraft(state: &AircraftKinematics, ts: DateTime<Utc>) -> Vec<u8> {
    let mut v = Vec::with_capacity(256);
    v.extend_from_slice(b"atc_trajectory_seed_v1");
    v.extend_from_slice(state.icao24.as_bytes());
    v.extend_from_slice(state.callsign.as_bytes());
    v.extend_from_slice(&state.lat.to_bits().to_le_bytes());
    v.extend_from_slice(&state.lon.to_bits().to_le_bytes());
    v.extend_from_slice(&state.alt_ft.to_bits().to_le_bytes());
    v.extend_from_slice(&state.velocity_kts.to_bits().to_le_bytes());
    v.extend_from_slice(&state.heading_deg.to_bits().to_le_bytes());
    v.extend_from_slice(&state.vertical_rate_fpm.to_bits().to_le_bytes());
    v.extend_from_slice(&ts.timestamp().to_le_bytes());
    v
}

fn seed_from_aircraft_pair(a: &AircraftKinematics, b: &AircraftKinematics, ts: DateTime<Utc>) -> Vec<u8> {
    // Order-stable seed: sort by icao24 to avoid A/B swaps producing different ensembles.
    let (x, y) = if a.icao24 <= b.icao24 { (a, b) } else { (b, a) };
    let mut v = Vec::with_capacity(512);
    v.extend_from_slice(b"atc_pair_trajectory_seed_v1");
    v.extend_from_slice(x.icao24.as_bytes());
    v.extend_from_slice(x.callsign.as_bytes());
    v.extend_from_slice(&x.lat.to_bits().to_le_bytes());
    v.extend_from_slice(&x.lon.to_bits().to_le_bytes());
    v.extend_from_slice(&x.alt_ft.to_bits().to_le_bytes());
    v.extend_from_slice(&x.velocity_kts.to_bits().to_le_bytes());
    v.extend_from_slice(&x.heading_deg.to_bits().to_le_bytes());
    v.extend_from_slice(&x.vertical_rate_fpm.to_bits().to_le_bytes());
    v.extend_from_slice(y.icao24.as_bytes());
    v.extend_from_slice(y.callsign.as_bytes());
    v.extend_from_slice(&y.lat.to_bits().to_le_bytes());
    v.extend_from_slice(&y.lon.to_bits().to_le_bytes());
    v.extend_from_slice(&y.alt_ft.to_bits().to_le_bytes());
    v.extend_from_slice(&y.velocity_kts.to_bits().to_le_bytes());
    v.extend_from_slice(&y.heading_deg.to_bits().to_le_bytes());
    v.extend_from_slice(&y.vertical_rate_fpm.to_bits().to_le_bytes());
    v.extend_from_slice(&ts.timestamp().to_le_bytes());
    v
}

fn provenance_bytes(state: &AircraftKinematics, ts: DateTime<Utc>, step: usize) -> Vec<u8> {
    let mut p = Vec::with_capacity(128);
    p.extend_from_slice(b"franklin_oversight|atc|");
    p.extend_from_slice(state.icao24.as_bytes());
    p.extend_from_slice(b"|");
    p.extend_from_slice(state.callsign.as_bytes());
    p.extend_from_slice(b"|ts:");
    p.extend_from_slice(ts.timestamp().to_string().as_bytes());
    p.extend_from_slice(b"|step:");
    p.extend_from_slice(step.to_string().as_bytes());
    p
}

fn pair_provenance_bytes(a: &AircraftKinematics, b: &AircraftKinematics, ts: DateTime<Utc>, step: usize) -> Vec<u8> {
    let mut p = Vec::with_capacity(192);
    p.extend_from_slice(b"franklin_oversight|atc_pair|");
    p.extend_from_slice(a.icao24.as_bytes());
    p.extend_from_slice(b"|");
    p.extend_from_slice(b.icao24.as_bytes());
    p.extend_from_slice(b"|ts:");
    p.extend_from_slice(ts.timestamp().to_string().as_bytes());
    p.extend_from_slice(b"|step:");
    p.extend_from_slice(step.to_string().as_bytes());
    p
}

fn qstate_from_noise(noise: &gaiaos_substrate::noise::isotropic_entanglement::EntanglementNoise) -> QState8 {
    // Use dimension RMS over channels as scores. This compresses 64×8 into 8 deterministic scores.
    let mut rms = [0.0f32; 8];
    for d in 0..8 {
        let mut s = 0.0f32;
        for c in 0..64 {
            let x = noise.channels[c][d];
            s += x * x;
        }
        rms[d] = (s / 64.0).sqrt();
    }
    QState8::from_scores(rms)
}

fn compute_separation_metrics(
    steps: usize,
    dt_sec: u64,
    lats_a: &[Vec<f64>],
    lons_a: &[Vec<f64>],
    alts_a: &[Vec<f64>],
    lats_b: &[Vec<f64>],
    lons_b: &[Vec<f64>],
    alts_b: &[Vec<f64>],
) -> PairSeparationMetrics {
    let ensemble_size = lats_a[0].len();

    let mut los_count = 0usize;
    let mut earliest: Option<u64> = None;
    let mut min_h = f64::INFINITY;
    let mut min_v = f64::INFINITY;

    for m in 0..ensemble_size {
        let mut member_violated = false;
        for t in 0..=steps {
            let h_nm = haversine_nm(lats_a[t][m], lons_a[t][m], lats_b[t][m], lons_b[t][m]);
            let v_ft = (alts_a[t][m] - alts_b[t][m]).abs();

            min_h = min_h.min(h_nm);
            min_v = min_v.min(v_ft);

            // FAA/ICAO conflict: BOTH violated
            let los = h_nm < 5.0 && v_ft < 1000.0;
            if los {
                let t_sec = (t as u64) * dt_sec;
                if earliest.map(|e| t_sec < e).unwrap_or(true) {
                    earliest = Some(t_sec);
                }
                member_violated = true;
            }
        }
        if member_violated {
            los_count += 1;
        }
    }

    let p = (los_count as f64) / (ensemble_size as f64);
    PairSeparationMetrics {
        los_probability: p,
        los_any_member: los_count > 0,
        earliest_los_sec: earliest,
        min_horizontal_nm: if min_h.is_finite() { min_h } else { 0.0 },
        min_vertical_ft: if min_v.is_finite() { min_v } else { 0.0 },
    }
}

fn haversine_nm(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r_earth_nm = 3440.065;

    let lat1_rad = lat1.to_radians();
    let lat2_rad = lat2.to_radians();
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();

    let a = (dlat / 2.0).sin().powi(2)
        + lat1_rad.cos() * lat2_rad.cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());

    r_earth_nm * c
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn predicts_and_summarizes() -> Result<()> {
        let s = AircraftKinematics {
            icao24: "abc123".to_string(),
            callsign: "TEST01".to_string(),
            lat: 41.0,
            lon: -72.0,
            alt_ft: 35000.0,
            velocity_kts: 450.0,
            heading_deg: 90.0,
            vertical_rate_fpm: 0.0,
        };
        let ts = Utc::now();
        let ens = predict_stochastic_trajectory(&s, ts, 60, 5)?;
        assert_eq!(ens.ensemble_size, 50);
        assert_eq!(ens.mean.points_mean.len(), 13);
        Ok(())
    }

    #[test]
    fn coupled_pair_metrics_are_bounded_and_deterministic() -> Result<()> {
        let a = AircraftKinematics {
            icao24: "aaa111".to_string(),
            callsign: "A".to_string(),
            lat: 41.0,
            lon: -72.0,
            alt_ft: 35000.0,
            velocity_kts: 450.0,
            heading_deg: 90.0,
            vertical_rate_fpm: 0.0,
        };
        let b = AircraftKinematics {
            icao24: "bbb222".to_string(),
            callsign: "B".to_string(),
            lat: 41.02,
            lon: -72.02,
            alt_ft: 35100.0,
            velocity_kts: 440.0,
            heading_deg: 270.0,
            vertical_rate_fpm: 0.0,
        };

        let ts = DateTime::<Utc>::from_timestamp(1735171200, 0).ok_or_else(|| anyhow!("bad ts"))?;
        let e1 = predict_coupled_pair_trajectory(&a, &b, ts, 60, 5)?;
        let e2 = predict_coupled_pair_trajectory(&a, &b, ts, 60, 5)?;

        assert!((e1.separation.los_probability - e2.separation.los_probability).abs() < 1e-12);
        assert_eq!(e1.separation.los_any_member, e2.separation.los_any_member);
        assert_eq!(e1.separation.earliest_los_sec, e2.separation.earliest_los_sec);
        assert!(e1.separation.los_probability >= 0.0 && e1.separation.los_probability <= 1.0);
        Ok(())
    }
}


