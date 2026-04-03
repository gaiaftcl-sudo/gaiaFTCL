//! GaiaOS 8D ATC Physics Engine - WASM
//!
//! Real 4D physics substrate for ATC visualization.
//! NO SYNTHETIC DATA. NO SIMULATIONS. REAL PHYSICS.
//!
//! ## 8D Vector: Ψ(aircraft) = [D0..D7]
//! - D0: Longitude (normalized -180..180 → -1..1)
//! - D1: Latitude (normalized -90..90 → -1..1)
//! - D2: Altitude (normalized 0..45000ft → 0..1)
//! - D3: Time (normalized diurnal 0..1)
//! - D4: Intent (flight plan adherence, speed normalized)
//! - D5: Risk (turbulence, proximity, weather)
//! - D6: Compliance (ATC clearance, route deviation)
//! - D7: Uncertainty (position accuracy, prediction confidence)

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::f64::consts::PI;
use wasm_bindgen::prelude::*;
use web_sys::{CanvasRenderingContext2d, HtmlCanvasElement, MessageEvent, WebSocket};

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);

    #[wasm_bindgen(js_namespace = console)]
    fn error(s: &str);
}

macro_rules! console_log {
    ($($t:tt)*) => (log(&format_args!($($t)*).to_string()))
}

// ═══════════════════════════════════════════════════════════════════════════
// 8D PHYSICS TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// 8D Vector - the fundamental unit of the physics substrate
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Vec8D {
    pub d: [f64; 8],
}

impl Vec8D {
    pub fn new(d0: f64, d1: f64, d2: f64, d3: f64, d4: f64, d5: f64, d6: f64, d7: f64) -> Self {
        Self {
            d: [d0, d1, d2, d3, d4, d5, d6, d7],
        }
    }

    pub fn zero() -> Self {
        Self { d: [0.0; 8] }
    }

    /// Magnitude in 8D space
    pub fn magnitude(&self) -> f64 {
        self.d.iter().map(|x| x * x).sum::<f64>().sqrt()
    }

    /// Dot product in 8D
    pub fn dot(&self, other: &Vec8D) -> f64 {
        self.d.iter().zip(other.d.iter()).map(|(a, b)| a * b).sum()
    }

    /// Linear interpolation in 8D
    pub fn lerp(&self, other: &Vec8D, t: f64) -> Vec8D {
        let mut result = [0.0; 8];
        for i in 0..8 {
            result[i] = self.d[i] + (other.d[i] - self.d[i]) * t;
        }
        Vec8D { d: result }
    }
}

/// 4D Velocity vector (spatial + temporal rate)
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Vec4D {
    pub x: f64, // East velocity (m/s)
    pub y: f64, // North velocity (m/s)
    pub z: f64, // Vertical velocity (m/s)
    pub t: f64, // Temporal rate (always 1.0 for normal time)
}

impl Vec4D {
    pub fn new(x: f64, y: f64, z: f64) -> Self {
        Self { x, y, z, t: 1.0 }
    }

    pub fn zero() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            z: 0.0,
            t: 1.0,
        }
    }

    pub fn magnitude_3d(&self) -> f64 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }
}

/// Aircraft entity in the physics engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Aircraft {
    pub icao24: String,
    pub callsign: String,
    pub aircraft_type: Option<String>,

    // 8D state vector
    pub state: Vec8D,

    // 4D velocity
    pub velocity: Vec4D,

    // Flight plan (target 8D state)
    pub flight_plan: Option<Vec8D>,

    // Visual properties
    pub heading_deg: f64,
    pub sprite_scale: f64,
    pub color: [u8; 4], // RGBA

    // Physics properties
    pub mass_kg: f64,
    pub drag_coefficient: f64,

    // vChip quantum state
    pub vchip_coherence: f64,
    pub last_vchip_tick: u64,
}

impl Aircraft {
    pub fn new(icao24: String, callsign: String) -> Self {
        Self {
            icao24,
            callsign,
            aircraft_type: None,
            state: Vec8D::zero(),
            velocity: Vec4D::zero(),
            flight_plan: None,
            heading_deg: 0.0,
            sprite_scale: 1.0,
            color: [0, 255, 204, 255], // Cyan
            mass_kg: 80000.0,          // ~A320
            drag_coefficient: 0.03,
            vchip_coherence: 1.0,
            last_vchip_tick: 0,
        }
    }

    /// Get altitude color based on D2 (altitude dimension)
    pub fn altitude_color(&self) -> [u8; 4] {
        let alt_norm = self.state.d[2];
        if alt_norm > 0.78 {
            // > FL350
            [0, 255, 204, 255] // Cyan - cruise
        } else if alt_norm > 0.40 {
            // > FL180
            [77, 166, 255, 255] // Blue - climb/descent
        } else if alt_norm > 0.11 {
            // > 5000ft
            [255, 204, 0, 255] // Yellow - terminal
        } else {
            [255, 102, 0, 255] // Orange - approach
        }
    }

    /// Get risk color based on D5 (risk dimension)
    pub fn risk_overlay_alpha(&self) -> u8 {
        let risk = self.state.d[5];
        (risk * 128.0).min(255.0) as u8
    }
}

/// Weather cell in the physics engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeatherCell {
    pub id: String,
    pub state: Vec8D,
    pub intensity: f64, // 0-1
    pub cell_type: WeatherType,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum WeatherType {
    Clear,
    Rain,
    Thunderstorm,
    Turbulence,
    Icing,
    Wind,
}

// ═══════════════════════════════════════════════════════════════════════════
// PHYSICS ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// The 8D Physics Engine
#[wasm_bindgen]
pub struct PhysicsEngine {
    // State
    tick: u64,
    world_time: f64,
    delta_t: f64,

    // Entities
    aircraft: HashMap<String, Aircraft>,
    weather: HashMap<String, WeatherCell>,

    // View state
    camera_lon: f64,
    camera_lat: f64,
    camera_zoom: f64, // Zoom level affects physics resolution

    // vChip integration
    vchip_scale: f64, // Current quantum scale
    vchip_coherence_threshold: f64,

    // Rendering
    canvas_width: f64,
    canvas_height: f64,

    // WebSocket for live streaming
    ws_connected: bool,
}

#[wasm_bindgen]
impl PhysicsEngine {
    #[wasm_bindgen(constructor)]
    pub fn new(canvas_width: f64, canvas_height: f64) -> PhysicsEngine {
        #[cfg(feature = "console_error_panic_hook")]
        console_error_panic_hook::set_once();

        console_log!("⚡ GaiaOS 8D Physics Engine initialized");
        console_log!("   Canvas: {}x{}", canvas_width, canvas_height);
        console_log!("   Mode: REAL_PHYSICS (NO SYNTHETIC DATA)");

        PhysicsEngine {
            tick: 0,
            world_time: 0.0,
            delta_t: 1.0 / 60.0, // 60 Hz physics
            aircraft: HashMap::new(),
            weather: HashMap::new(),
            camera_lon: -98.0,
            camera_lat: 39.0,
            camera_zoom: 4.0,
            vchip_scale: 1.0,
            vchip_coherence_threshold: 0.5,
            canvas_width,
            canvas_height,
            ws_connected: false,
        }
    }

    /// Physics tick - advance the simulation
    #[wasm_bindgen]
    pub fn tick(&mut self) {
        self.tick += 1;
        self.world_time += self.delta_t;

        // Update D3 (time dimension) for all aircraft
        let time_of_day = (self.world_time % 86400.0) / 86400.0;

        for aircraft in self.aircraft.values_mut() {
            // Update time dimension
            aircraft.state.d[3] = time_of_day;

            // Apply velocity to position (D0, D1, D2)
            // Convert velocity (m/s) to degree change
            let meters_per_degree_lon = 111320.0 * (aircraft.state.d[1] * 90.0).to_radians().cos();
            let meters_per_degree_lat = 111320.0;

            // D0: Longitude
            aircraft.state.d[0] +=
                (aircraft.velocity.x / meters_per_degree_lon) * self.delta_t / 180.0;

            // D1: Latitude
            aircraft.state.d[1] +=
                (aircraft.velocity.y / meters_per_degree_lat) * self.delta_t / 90.0;

            // D2: Altitude (normalized)
            let alt_change_ft = aircraft.velocity.z * 3.28084 * self.delta_t;
            aircraft.state.d[2] += alt_change_ft / 45000.0;
            aircraft.state.d[2] = aircraft.state.d[2].clamp(0.0, 1.0);

            // Flight plan following (D4: intent)
            if let Some(ref plan) = aircraft.flight_plan {
                let deviation = (aircraft.state.d[0] - plan.d[0]).abs()
                    + (aircraft.state.d[1] - plan.d[1]).abs();
                aircraft.state.d[4] = (1.0 - deviation * 10.0).clamp(0.0, 1.0);
            }

            // vChip coherence decay
            if self.tick - aircraft.last_vchip_tick > 60 {
                aircraft.vchip_coherence *= 0.99;
            }

            // Update uncertainty based on vChip coherence
            aircraft.state.d[7] = 1.0 - aircraft.vchip_coherence;
        }
    }

    /// Set camera position
    #[wasm_bindgen]
    pub fn set_camera(&mut self, lon: f64, lat: f64, zoom: f64) {
        self.camera_lon = lon;
        self.camera_lat = lat;
        self.camera_zoom = zoom;

        // Update vChip scale based on zoom
        // Higher zoom = finer quantum resolution
        self.vchip_scale = 2.0_f64.powf(zoom - 4.0);

        console_log!(
            "📍 Camera: ({:.2}, {:.2}) zoom={:.1} vChip_scale={:.3}",
            lon,
            lat,
            zoom,
            self.vchip_scale
        );
    }

    /// Ingest aircraft data from JSON
    #[wasm_bindgen]
    pub fn ingest_aircraft(&mut self, json_data: &str) -> Result<u32, JsValue> {
        let data: Vec<AircraftData> = serde_json::from_str(json_data)
            .map_err(|e| JsValue::from_str(&format!("JSON parse error: {}", e)))?;

        let mut count = 0;
        for ac in data {
            let icao = ac.icao24.clone();

            let aircraft = self.aircraft.entry(icao.clone()).or_insert_with(|| {
                Aircraft::new(icao.clone(), ac.callsign.clone().unwrap_or_default())
            });

            // Update 8D state
            if let Some(lon) = ac.center_lon {
                aircraft.state.d[0] = lon / 180.0;
            }
            if let Some(lat) = ac.center_lat {
                aircraft.state.d[1] = lat / 90.0;
            }
            if let Some(alt) = ac.altitude_ft.or(ac.center_alt_m.map(|m| m * 3.28084)) {
                aircraft.state.d[2] = (alt / 45000.0).clamp(0.0, 1.0);
            }

            // Update velocity
            if let Some(vel) = ac.velocity_kts {
                let hdg_rad = ac.heading_deg.unwrap_or(0.0).to_radians();
                let vel_ms = vel * 0.514444; // kts to m/s
                aircraft.velocity.x = vel_ms * hdg_rad.sin();
                aircraft.velocity.y = vel_ms * hdg_rad.cos();
            }
            if let Some(vs) = ac.vertical_rate_fpm {
                aircraft.velocity.z = vs / 196.85; // fpm to m/s
            }

            // Update heading
            if let Some(hdg) = ac.heading_deg {
                aircraft.heading_deg = hdg;
            }

            // Update callsign
            if let Some(cs) = ac.callsign {
                aircraft.callsign = cs;
            }

            // Update 8D vector from data if provided
            if let Some(d_vec) = ac.d_vec {
                if d_vec.len() == 8 {
                    for i in 0..8 {
                        aircraft.state.d[i] = d_vec[i];
                    }
                }
            }

            // Mark vChip tick
            aircraft.last_vchip_tick = self.tick;
            aircraft.vchip_coherence = 1.0;

            count += 1;
        }

        Ok(count)
    }

    /// Render to canvas
    #[wasm_bindgen]
    pub fn render(&self, ctx: &CanvasRenderingContext2d) {
        // Clear canvas
        ctx.set_fill_style(&JsValue::from_str("#0a0a12"));
        ctx.fill_rect(0.0, 0.0, self.canvas_width, self.canvas_height);

        // Draw grid (8D projection lines)
        self.draw_grid(ctx);

        // Draw weather cells
        for weather in self.weather.values() {
            self.draw_weather(ctx, weather);
        }

        // Draw aircraft
        for aircraft in self.aircraft.values() {
            self.draw_aircraft(ctx, aircraft);
        }

        // Draw HUD
        self.draw_hud(ctx);
    }

    fn draw_grid(&self, ctx: &CanvasRenderingContext2d) {
        ctx.set_stroke_style(&JsValue::from_str("rgba(100, 100, 140, 0.2)"));
        ctx.set_line_width(1.0);

        let grid_spacing = 50.0 * self.vchip_scale;

        // Vertical lines
        let mut x = 0.0;
        while x < self.canvas_width {
            ctx.begin_path();
            ctx.move_to(x, 0.0);
            ctx.line_to(x, self.canvas_height);
            ctx.stroke();
            x += grid_spacing;
        }

        // Horizontal lines
        let mut y = 0.0;
        while y < self.canvas_height {
            ctx.begin_path();
            ctx.move_to(0.0, y);
            ctx.line_to(self.canvas_width, y);
            ctx.stroke();
            y += grid_spacing;
        }
    }

    fn draw_weather(&self, ctx: &CanvasRenderingContext2d, weather: &WeatherCell) {
        let (x, y) = self.world_to_screen(weather.state.d[0] * 180.0, weather.state.d[1] * 90.0);

        if x < -50.0 || x > self.canvas_width + 50.0 || y < -50.0 || y > self.canvas_height + 50.0 {
            return;
        }

        let radius = 20.0 * self.vchip_scale * weather.intensity;
        let color = match weather.cell_type {
            WeatherType::Clear => "rgba(0, 204, 102, 0.3)",
            WeatherType::Rain => "rgba(0, 255, 0, 0.4)",
            WeatherType::Thunderstorm => "rgba(255, 0, 0, 0.5)",
            WeatherType::Turbulence => "rgba(255, 165, 0, 0.4)",
            WeatherType::Icing => "rgba(0, 200, 255, 0.4)",
            WeatherType::Wind => "rgba(100, 100, 255, 0.3)",
        };

        ctx.set_fill_style(&JsValue::from_str(color));
        ctx.begin_path();
        ctx.arc(x, y, radius, 0.0, 2.0 * PI).unwrap();
        ctx.fill();
    }

    fn draw_aircraft(&self, ctx: &CanvasRenderingContext2d, aircraft: &Aircraft) {
        // Convert 8D state to screen coordinates
        let lon = aircraft.state.d[0] * 180.0;
        let lat = aircraft.state.d[1] * 90.0;
        let (x, y) = self.world_to_screen(lon, lat);

        // Skip if off screen
        if x < -50.0 || x > self.canvas_width + 50.0 || y < -50.0 || y > self.canvas_height + 50.0 {
            return;
        }

        // Scale based on zoom and altitude
        let base_size = 12.0;
        let alt_scale = 0.5 + aircraft.state.d[2] * 0.5; // Larger at higher altitude
        let size = base_size * alt_scale * (self.camera_zoom / 4.0).sqrt();

        // Color based on altitude
        let color = aircraft.altitude_color();
        let color_str = format!(
            "rgba({}, {}, {}, {})",
            color[0],
            color[1],
            color[2],
            (aircraft.vchip_coherence * 255.0) as u8
        );

        ctx.save();
        ctx.translate(x, y).unwrap();
        ctx.rotate((aircraft.heading_deg - 90.0).to_radians())
            .unwrap();

        // Draw aircraft sprite (proper aviation icon)
        ctx.set_fill_style(&JsValue::from_str(&color_str));
        ctx.begin_path();

        // Aircraft shape (pointing right, rotated by heading)
        ctx.move_to(size, 0.0); // Nose
        ctx.line_to(-size * 0.5, -size * 0.8); // Left wing tip
        ctx.line_to(-size * 0.3, 0.0); // Left wing root
        ctx.line_to(-size * 0.5, size * 0.8); // Right wing tip
        ctx.close_path();
        ctx.fill();

        // Draw tail
        ctx.begin_path();
        ctx.move_to(-size * 0.3, 0.0);
        ctx.line_to(-size * 0.8, -size * 0.3);
        ctx.line_to(-size * 0.8, size * 0.3);
        ctx.close_path();
        ctx.fill();

        ctx.restore();

        // Draw flight plan vector (D4: intent)
        if let Some(ref plan) = aircraft.flight_plan {
            let plan_lon = plan.d[0] * 180.0;
            let plan_lat = plan.d[1] * 90.0;
            let (px, py) = self.world_to_screen(plan_lon, plan_lat);

            ctx.set_stroke_style(&JsValue::from_str("rgba(168, 85, 247, 0.5)"));
            ctx.set_line_width(1.0);
            ctx.set_line_dash(&js_sys::Array::of2(
                &JsValue::from(4.0),
                &JsValue::from(4.0),
            ))
            .unwrap();
            ctx.begin_path();
            ctx.move_to(x, y);
            ctx.line_to(px, py);
            ctx.stroke();
            ctx.set_line_dash(&js_sys::Array::new()).unwrap();
        }

        // Draw velocity vector
        let vel_scale = 0.1 * self.vchip_scale;
        let vx = aircraft.velocity.x * vel_scale;
        let vy = -aircraft.velocity.y * vel_scale; // Flip Y

        ctx.set_stroke_style(&JsValue::from_str("rgba(255, 255, 255, 0.3)"));
        ctx.set_line_width(1.0);
        ctx.begin_path();
        ctx.move_to(x, y);
        ctx.line_to(x + vx, y + vy);
        ctx.stroke();

        // Draw callsign label (only at higher zoom)
        if self.camera_zoom >= 6.0 && !aircraft.callsign.is_empty() {
            ctx.set_font("10px JetBrains Mono, monospace");
            ctx.set_fill_style(&JsValue::from_str(&color_str));
            ctx.fill_text(&aircraft.callsign, x + size + 4.0, y + 3.0)
                .unwrap();
        }

        // Draw risk overlay (D5)
        let risk_alpha = aircraft.risk_overlay_alpha();
        if risk_alpha > 20 {
            ctx.set_fill_style(&JsValue::from_str(&format!(
                "rgba(255, 51, 85, {})",
                risk_alpha as f64 / 255.0
            )));
            ctx.begin_path();
            ctx.arc(x, y, size * 2.0, 0.0, 2.0 * PI).unwrap();
            ctx.fill();
        }
    }

    fn draw_hud(&self, ctx: &CanvasRenderingContext2d) {
        ctx.set_font("12px JetBrains Mono, monospace");
        ctx.set_fill_style(&JsValue::from_str("#e8e8f0"));

        let y = 20.0;
        ctx.fill_text(
            &format!(
                "⚡ GaiaOS 8D Physics | Tick: {} | Aircraft: {}",
                self.tick,
                self.aircraft.len()
            ),
            10.0,
            y,
        )
        .unwrap();
        ctx.fill_text(
            &format!(
                "   vChip Scale: {:.3} | Zoom: {:.1}",
                self.vchip_scale, self.camera_zoom
            ),
            10.0,
            y + 16.0,
        )
        .unwrap();
    }

    fn world_to_screen(&self, lon: f64, lat: f64) -> (f64, f64) {
        // Web Mercator projection
        let scale = 256.0 * 2.0_f64.powf(self.camera_zoom);

        let x = (lon + 180.0) / 360.0 * scale;
        let lat_rad = lat.to_radians();
        let y = (1.0 - (lat_rad.tan() + 1.0 / lat_rad.cos()).ln() / PI) / 2.0 * scale;

        // Center on camera
        let cam_x = (self.camera_lon + 180.0) / 360.0 * scale;
        let cam_lat_rad = self.camera_lat.to_radians();
        let cam_y = (1.0 - (cam_lat_rad.tan() + 1.0 / cam_lat_rad.cos()).ln() / PI) / 2.0 * scale;

        let screen_x = (x - cam_x) + self.canvas_width / 2.0;
        let screen_y = (y - cam_y) + self.canvas_height / 2.0;

        (screen_x, screen_y)
    }

    /// Get aircraft count
    #[wasm_bindgen]
    pub fn aircraft_count(&self) -> u32 {
        self.aircraft.len() as u32
    }

    /// Get current tick
    #[wasm_bindgen]
    pub fn current_tick(&self) -> u64 {
        self.tick
    }

    /// Get vChip scale
    #[wasm_bindgen]
    pub fn get_vchip_scale(&self) -> f64 {
        self.vchip_scale
    }

    /// Clear all aircraft (for refresh)
    #[wasm_bindgen]
    pub fn clear_aircraft(&mut self) {
        self.aircraft.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA STRUCTURES FOR JSON INGESTION
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Deserialize)]
struct AircraftData {
    icao24: String,
    callsign: Option<String>,
    center_lat: Option<f64>,
    center_lon: Option<f64>,
    center_alt_m: Option<f64>,
    altitude_ft: Option<f64>,
    velocity_kts: Option<f64>,
    velocity_ms: Option<f64>,
    heading_deg: Option<f64>,
    vertical_rate_fpm: Option<f64>,
    d_vec: Option<Vec<f64>>,
    aircraft_type: Option<String>,
}
