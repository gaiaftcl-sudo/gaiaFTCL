use anyhow::{anyhow, Result};
use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;

use crate::Arango;

#[derive(Clone)]
pub struct AppState {
    pub arango: Arango,
}

#[derive(Deserialize)]
pub struct RouteRequest {
    pub start_lat: f64,
    pub start_lon: f64,
    pub end_lat: f64,
    pub end_lon: f64,
    pub departure_time: i64,
}

#[derive(Serialize)]
pub struct RouteResponse {
    pub waypoints: Vec<Waypoint>,
    pub total_distance_nm: f64,
    pub fuel_savings_liters: f64,
    pub with_currents: bool,
}

#[derive(Serialize)]
pub struct Waypoint {
    pub lat: f64,
    pub lon: f64,
    pub timestamp: i64,
}

#[derive(Clone)]
struct OceanTileLite {
    lat: f64,
    lon: f64,
    current_u: Option<f64>,
    current_v: Option<f64>,
}

pub fn routing_routes(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/ocean/routing/optimize", post(optimize_route))
        .with_state(state)
}

pub async fn optimize_route(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RouteRequest>,
) -> Result<Json<RouteResponse>, StatusCode> {
    let tiles = query_ocean_tiles_corridor(
        &state.arango,
        req.start_lat,
        req.start_lon,
        req.end_lat,
        req.end_lon,
        req.departure_time,
    )
    .await
    .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    if tiles.is_empty() {
        return Err(StatusCode::SERVICE_UNAVAILABLE);
    }

    let mut waypoints = vec![Waypoint {
        lat: req.start_lat,
        lon: req.start_lon,
        timestamp: req.departure_time,
    }];

    let mut current_pos = (req.start_lat, req.start_lon);
    let goal = (req.end_lat, req.end_lon);
    let mut time = req.departure_time;

    let mut used_currents = false;
    let max_steps = 240usize; // 10 days at 1h steps (bounded compute)

    for _ in 0..max_steps {
        if distance_nm(current_pos, goal) <= 10.0 {
            break;
        }

        let nearest = tiles
            .iter()
            .min_by(|a, b| {
                distance_nm((a.lat, a.lon), current_pos)
                    .partial_cmp(&distance_nm((b.lat, b.lon), current_pos))
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;

        let bearing_to_goal = bearing(current_pos, goal);

        let current_u_kts = nearest.current_u.unwrap_or(0.0) * 1.94384;
        let current_v_kts = nearest.current_v.unwrap_or(0.0) * 1.94384;
        if current_u_kts.abs() > 0.01 || current_v_kts.abs() > 0.01 {
            used_currents = true;
        }

        let ship_speed_kts = 15.0;
        let next_pos = advance_position(
            current_pos,
            bearing_to_goal,
            ship_speed_kts,
            current_u_kts,
            current_v_kts,
            1.0,
        );

        current_pos = next_pos;
        time += 3600;
        waypoints.push(Waypoint {
            lat: current_pos.0,
            lon: current_pos.1,
            timestamp: time,
        });
    }

    let direct_distance = distance_nm((req.start_lat, req.start_lon), goal);
    let actual_distance = waypoints
        .windows(2)
        .map(|w| distance_nm((w[0].lat, w[0].lon), (w[1].lat, w[1].lon)))
        .sum::<f64>();

    // Deterministic fuel model: 0.1 L/nm
    let fuel_savings = (direct_distance - actual_distance).abs() * 0.1;

    Ok(Json(RouteResponse {
        waypoints,
        total_distance_nm: actual_distance,
        fuel_savings_liters: fuel_savings,
        with_currents: used_currents,
    }))
}

async fn query_ocean_tiles_corridor(
    arango: &Arango,
    start_lat: f64,
    start_lon: f64,
    end_lat: f64,
    end_lon: f64,
    departure_time: i64,
) -> Result<Vec<OceanTileLite>> {
    let lat_min = start_lat.min(end_lat) - 2.0;
    let lat_max = start_lat.max(end_lat) + 2.0;
    let lon_min = start_lon.min(end_lon) - 2.0;
    let lon_max = start_lon.max(end_lon) + 2.0;

    // Corridor time window: +/- 6 hours around departure_time
    let t_min = departure_time - 6 * 3600;
    let t_max = departure_time + 6 * 3600;

    let aql = r#"
FOR t IN ocean_tiles
  FILTER t.location.coordinates[1] >= @lat_min AND t.location.coordinates[1] <= @lat_max
  FILTER t.location.coordinates[0] >= @lon_min AND t.location.coordinates[0] <= @lon_max
  FILTER t.valid_time >= @t_min AND t.valid_time <= @t_max
  FILTER t.depth_m == null OR t.depth_m <= 10
  SORT t.valid_time DESC
  LIMIT 5000
  RETURN {
    lat: t.location.coordinates[1],
    lon: t.location.coordinates[0],
    cu: t.state.current_u,
    cv: t.state.current_v
  }
"#;

    let docs = arango
        .aql_raw(
            aql,
            serde_json::json!({
                "lat_min": lat_min,
                "lat_max": lat_max,
                "lon_min": lon_min,
                "lon_max": lon_max,
                "t_min": t_min,
                "t_max": t_max
            }),
        )
        .await?;

    let arr = docs.as_array().cloned().unwrap_or_default();
    let mut out = Vec::with_capacity(arr.len());
    for v in arr {
        let lat = v.get("lat").and_then(|x| x.as_f64()).unwrap_or(0.0);
        let lon = v.get("lon").and_then(|x| x.as_f64()).unwrap_or(0.0);
        if lat == 0.0 && lon == 0.0 {
            continue;
        }
        out.push(OceanTileLite {
            lat,
            lon,
            current_u: v.get("cu").and_then(|x| x.as_f64()),
            current_v: v.get("cv").and_then(|x| x.as_f64()),
        });
    }

    if out.is_empty() {
        return Err(anyhow!("no ocean tiles found for routing corridor"));
    }
    Ok(out)
}

fn distance_nm(a: (f64, f64), b: (f64, f64)) -> f64 {
    const R: f64 = 3440.065;
    let dlat = (b.0 - a.0).to_radians();
    let dlon = (b.1 - a.1).to_radians();
    let aa = (dlat / 2.0).sin().powi(2)
        + a.0.to_radians().cos() * b.0.to_radians().cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * aa.sqrt().atan2((1.0 - aa).sqrt());
    R * c
}

fn bearing(from: (f64, f64), to: (f64, f64)) -> f64 {
    let lat1 = from.0.to_radians();
    let lat2 = to.0.to_radians();
    let dlon = (to.1 - from.1).to_radians();
    let y = dlon.sin() * lat2.cos();
    let x = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * dlon.cos();
    y.atan2(x).to_degrees()
}

fn advance_position(
    pos: (f64, f64),
    bearing_deg: f64,
    ship_speed_kts: f64,
    current_u_kts: f64,
    current_v_kts: f64,
    hours: f64,
) -> (f64, f64) {
    let brng = bearing_deg.to_radians();
    let ship_u = ship_speed_kts * brng.sin();
    let ship_v = ship_speed_kts * brng.cos();
    let total_u = ship_u + current_u_kts;
    let total_v = ship_v + current_v_kts;

    let dist_nm = (total_u.powi(2) + total_v.powi(2)).sqrt() * hours;
    let actual_bearing = total_u.atan2(total_v).to_degrees();

    const R: f64 = 3440.065;
    let lat1 = pos.0.to_radians();
    let lon1 = pos.1.to_radians();
    let br = actual_bearing.to_radians();

    let lat2 = (lat1.sin() * (dist_nm / R).cos() + lat1.cos() * (dist_nm / R).sin() * br.cos())
        .asin();
    let lon2 = lon1
        + (br.sin() * (dist_nm / R).sin() * lat1.cos())
            .atan2((dist_nm / R).cos() - lat1.sin() * lat2.sin());

    (lat2.to_degrees(), lon2.to_degrees())
}

pub async fn health() -> Result<Json<Value>, StatusCode> {
    Ok(Json(serde_json::json!({"status":"ok","service":"ocean-routing"})))
}


