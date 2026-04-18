/*!
 * Windy API Integration
 * 
 * High-resolution global weather models (ECMWF, GFS, ICON)
 */

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Deserialize)]
pub struct WindyForecast {
    pub lat: f64,
    pub lon: f64,
    pub model: String,  // "ecmwf", "gfs", "icon"
    pub wind_u: Vec<f64>,  // m/s (west-east component)
    pub wind_v: Vec<f64>,  // m/s (south-north component)
    pub temp: Vec<f64>,    // Celsius
    pub pressure: Vec<f64>,  // hPa
    pub altitude_levels: Vec<u32>,  // meters
    pub forecast_times: Vec<String>,
}

pub struct WindyClient {
    api_key: String,
    base_url: String,
    http_client: reqwest::Client,
}

impl WindyClient {
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            base_url: "https://api.windy.com/api".to_string(),
            http_client: reqwest::Client::new(),
        }
    }
    
    /// Fetch point forecast for specific location and altitude
    pub async fn fetch_point_forecast(
        &self,
        lat: f64,
        lon: f64,
        model: &str,  // "ecmwf", "gfs", "icon"
        levels: &[&str]  // "surface", "950h", "925h", "900h", "850h", "700h", "500h", "300h", "200h"
    ) -> Result<WindyForecast, Box<dyn std::error::Error>> {
        let url = format!("{}/point-forecast/v2", self.base_url);
        
        let params = serde_json::json!({
            "lat": lat,
            "lon": lon,
            "model": model,
            "levels": levels,
            "key": self.api_key
        });
        
        let response = self.http_client
            .get(&url)
            .query(&params)
            .send()
            .await?
            .json::<WindyForecast>()
            .await?;
        
        Ok(response)
    }
    
    /// Stream weather updates for a grid
    pub async fn stream_grid_weather(
        &self,
        bbox: (f64, f64, f64, f64),  // min_lat, min_lon, max_lat, max_lon
        resolution: f64,  // degrees (e.g., 0.5 = ~55km)
        model: &str
    ) -> Result<Vec<WeatherGridPoint>, Box<dyn std::error::Error>> {
        let mut grid_points = Vec::new();
        
        let mut lat = bbox.0;
        while lat <= bbox.2 {
            let mut lon = bbox.1;
            while lon <= bbox.3 {
                let forecast = self.fetch_point_forecast(
                    lat,
                    lon,
                    model,
                    &["surface", "700h", "300h"]
                ).await?;
                
                grid_points.push(WeatherGridPoint {
                    lat,
                    lon,
                    wind_speed_kts: calculate_wind_speed(&forecast),
                    wind_dir: calculate_wind_direction(&forecast),
                    turbulence_intensity: estimate_turbulence(&forecast),
                });
                
                lon += resolution;
            }
            lat += resolution;
        }
        
        Ok(grid_points)
    }
    
    /// Convert Windy data to GaiaOS 8D WeatherEvent
    pub fn to_8d_event(&self, forecast: &WindyForecast, altitude_ft: f64) -> crate::event_schema::WeatherEvent8D {
        use crate::event_schema::*;
        
        // Find closest altitude level
        let altitude_m = altitude_ft * 0.3048;
        let level_idx = forecast.altitude_levels.iter()
            .position(|&alt| (alt as f64 - altitude_m).abs() < 500.0)
            .unwrap_or(0);
        
        let wind_u = forecast.wind_u[level_idx];
        let wind_v = forecast.wind_v[level_idx];
        let wind_speed = (wind_u.powi(2) + wind_v.powi(2)).sqrt();
        let wind_dir = wind_v.atan2(wind_u).to_degrees();
        
        // Estimate turbulence from wind shear
        let turbulence = if forecast.wind_u.len() > 1 {
            let shear = (forecast.wind_u[level_idx] - forecast.wind_u[level_idx.saturating_sub(1)]).abs();
            match shear {
                s if s > 15.0 => TurbulenceLevel::Severe,
                s if s > 10.0 => TurbulenceLevel::Moderate,
                s if s > 5.0 => TurbulenceLevel::Light,
                _ => TurbulenceLevel::None,
            }
        } else {
            TurbulenceLevel::None
        };
        
        WeatherEvent8D {
            cell_id: format!("WINDY_{}_{}", forecast.lat, forecast.lon),
            wx_type: if wind_speed > 25.0 {
                WeatherEventType::JetStream
            } else {
                WeatherEventType::Turbulence
            },
            center_lat: forecast.lat,
            center_lon: forecast.lon,
            radius_nm: 50.0,  // Grid resolution dependent
            altitude_range_ft: (altitude_ft - 1000.0, altitude_ft + 1000.0),
            timestamp: Utc::now(),
            duration_forecast_min: Some(360.0),  // 6 hours ahead
            movement_vector: Some(MovementVector {
                bearing: wind_dir,
                speed_kts: wind_speed * 1.94384,  // m/s to knots
            }),
            severity: match turbulence {
                TurbulenceLevel::Severe => WeatherSeverity::Severe,
                TurbulenceLevel::Moderate => WeatherSeverity::Moderate,
                _ => WeatherSeverity::Minor,
            },
            turbulence,
            icing: estimate_icing(forecast.temp[level_idx]),
            precipitation: PrecipitationType::None,
            signature_8d: Signature8D {
                truth: 0.85,  // Model-based
                virtue: 0.70,
                time: 0.90,
                space: 0.80,
                causal: 0.95,  // High predictive power
                social: 0.30,
                risk: match turbulence {
                    TurbulenceLevel::Severe => 0.85,
                    TurbulenceLevel::Moderate => 0.60,
                    _ => 0.30,
                },
                economic: 0.50,  // Affects fuel burn
            },
            forecast: None,
            affected_flights: vec![],
            affected_airports: vec![],
        }
    }
}

#[derive(Debug, Serialize)]
pub struct WeatherGridPoint {
    pub lat: f64,
    pub lon: f64,
    pub wind_speed_kts: f64,
    pub wind_dir: f64,
    pub turbulence_intensity: f32,
}

fn calculate_wind_speed(forecast: &WindyForecast) -> f64 {
    let u = forecast.wind_u[0];
    let v = forecast.wind_v[0];
    (u.powi(2) + v.powi(2)).sqrt() * 1.94384  // m/s to knots
}

fn calculate_wind_direction(forecast: &WindyForecast) -> f64 {
    let u = forecast.wind_u[0];
    let v = forecast.wind_v[0];
    (v.atan2(u).to_degrees() + 360.0) % 360.0
}

fn estimate_turbulence(forecast: &WindyForecast) -> f32 {
    // Simple shear-based turbulence estimation
    if forecast.wind_u.len() < 2 {
        return 0.0;
    }
    
    let max_shear = forecast.wind_u.windows(2)
        .map(|w| (w[1] - w[0]).abs())
        .max_by(|a, b| a.partial_cmp(b).unwrap())
        .unwrap_or(0.0);
    
    (max_shear / 20.0).min(1.0) as f32
}

fn estimate_icing(temp_c: f64) -> crate::event_schema::IcingLevel {
    use crate::event_schema::IcingLevel;
    
    match temp_c {
        t if t > 0.0 => IcingLevel::None,
        t if t > -10.0 => IcingLevel::Light,
        t if t > -20.0 => IcingLevel::Moderate,
        _ => IcingLevel::Severe,
    }
}
