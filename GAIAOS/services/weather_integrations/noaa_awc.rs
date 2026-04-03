/*!
 * NOAA Aviation Weather Center Integration
 * 
 * Real-time aviation weather from aviationweather.gov
 */

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

/// SIGMET from AWC
#[derive(Debug, Deserialize)]
pub struct AwcSigmet {
    pub raw_sigmet: String,
    pub valid_time_from: String,
    pub valid_time_to: String,
    pub hazard: String,  // "CONVECTIVE", "TURB", "ICE", "ASH"
    pub severity: String,  // "SEV", "EMBD", "ISOL"
    pub altitudes: (u32, u32),  // feet
    pub area: Vec<(f64, f64)>,  // lat/lon polygon
}

/// Turbulence forecast (GTG)
#[derive(Debug, Deserialize)]
pub struct GtgTurbulence {
    pub forecast_time: String,
    pub altitude_ft: u32,
    pub latitude: f64,
    pub longitude: f64,
    pub intensity: u8,  // 0-8 scale
}

/// Icing forecast (CIP/FIP)
#[derive(Debug, Deserialize)]
pub struct IcingForecast {
    pub forecast_time: String,
    pub altitude_ft: u32,
    pub latitude: f64,
    pub longitude: f64,
    pub severity: String,  // "TRACE", "LIGHT", "MOD", "SEV"
    pub probability: f32,  // 0.0-1.0
}

pub struct NoaaAwcClient {
    base_url: String,
    http_client: reqwest::Client,
}

impl NoaaAwcClient {
    pub fn new() -> Self {
        Self {
            base_url: "https://aviationweather.gov/api/data".to_string(),
            http_client: reqwest::Client::new(),
        }
    }
    
    /// Fetch current SIGMETs
    pub async fn fetch_sigmets(&self) -> Result<Vec<AwcSigmet>, Box<dyn std::error::Error>> {
        let url = format!("{}/sigmet?format=json&hazard=all", self.base_url);
        
        let response = self.http_client
            .get(&url)
            .send()
            .await?
            .json::<Vec<AwcSigmet>>()
            .await?;
        
        Ok(response)
    }
    
    /// Fetch turbulence forecast (Graphical Turbulence Guidance)
    pub async fn fetch_turbulence_gtg(
        &self,
        bbox: (f64, f64, f64, f64),  // min_lat, min_lon, max_lat, max_lon
        altitude_ft: u32
    ) -> Result<Vec<GtgTurbulence>, Box<dyn std::error::Error>> {
        // GTG data comes as GRIB2, need to parse
        let url = format!(
            "{}/gtg?bbox={},{},{},{}&alt={}",
            self.base_url, bbox.0, bbox.1, bbox.2, bbox.3, altitude_ft
        );
        
        let response = self.http_client
            .get(&url)
            .send()
            .await?
            .json::<Vec<GtgTurbulence>>()
            .await?;
        
        Ok(response)
    }
    
    /// Fetch icing forecast (Current Icing Product / Forecast Icing Product)
    pub async fn fetch_icing_forecast(
        &self,
        bbox: (f64, f64, f64, f64),
        altitude_ft: u32
    ) -> Result<Vec<IcingForecast>, Box<dyn std::error::Error>> {
        let url = format!(
            "{}/cip?bbox={},{},{},{}&alt={}",
            self.base_url, bbox.0, bbox.1, bbox.2, bbox.3, altitude_ft
        );
        
        let response = self.http_client
            .get(&url)
            .send()
            .await?
            .json::<Vec<IcingForecast>>()
            .await?;
        
        Ok(response)
    }
    
    /// Convert AWC data to GaiaOS 8D WeatherEvent
    pub fn to_8d_event(&self, sigmet: &AwcSigmet) -> crate::event_schema::WeatherEvent8D {
        use crate::event_schema::*;
        
        // Calculate center of polygon
        let center = sigmet.area.iter().fold((0.0, 0.0), |acc, p| {
            (acc.0 + p.0, acc.1 + p.1)
        });
        let center = (
            center.0 / sigmet.area.len() as f64,
            center.1 / sigmet.area.len() as f64
        );
        
        // Calculate radius (approximate)
        let radius = sigmet.area.iter()
            .map(|p| haversine_distance(center, *p))
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(0.0);
        
        WeatherEvent8D {
            cell_id: format!("SIGMET_{}", uuid::Uuid::new_v4()),
            wx_type: match sigmet.hazard.as_str() {
                "CONVECTIVE" => WeatherEventType::ThunderstormCell,
                "TURB" => WeatherEventType::Turbulence,
                "ICE" => WeatherEventType::Icing,
                "ASH" => WeatherEventType::VolcanicAsh,
                _ => WeatherEventType::ConvectiveSigmet,
            },
            center_lat: center.0,
            center_lon: center.1,
            radius_nm: radius,
            altitude_range_ft: (sigmet.altitudes.0 as f64, sigmet.altitudes.1 as f64),
            timestamp: Utc::now(),
            duration_forecast_min: None,
            movement_vector: None,
            severity: match sigmet.severity.as_str() {
                "SEV" => WeatherSeverity::Severe,
                "EMBD" => WeatherSeverity::Moderate,
                _ => WeatherSeverity::Minor,
            },
            turbulence: match sigmet.hazard.as_str() {
                "TURB" => TurbulenceLevel::Severe,
                _ => TurbulenceLevel::None,
            },
            icing: match sigmet.hazard.as_str() {
                "ICE" => IcingLevel::Severe,
                _ => IcingLevel::None,
            },
            precipitation: PrecipitationType::None,
            signature_8d: compute_8d_signature_for_weather(&sigmet),
            forecast: None,
            affected_flights: vec![],
            affected_airports: vec![],
        }
    }
}

fn haversine_distance(p1: (f64, f64), p2: (f64, f64)) -> f64 {
    const R: f64 = 3440.065; // Earth radius in nautical miles
    
    let lat1 = p1.0.to_radians();
    let lat2 = p2.0.to_radians();
    let dlat = (p2.0 - p1.0).to_radians();
    let dlon = (p2.1 - p1.1).to_radians();
    
    let a = (dlat / 2.0).sin().powi(2) +
            lat1.cos() * lat2.cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    
    R * c
}

fn compute_8d_signature_for_weather(sigmet: &AwcSigmet) -> crate::event_schema::Signature8D {
    use crate::event_schema::Signature8D;
    
    Signature8D {
        truth: 0.95,  // NOAA AWC is highly verified
        virtue: 0.90,  // Safety-critical information
        time: 0.95,    // Real-time
        space: 0.98,   // Precise polygons
        causal: 0.75,  // Some predictive element
        social: 0.60,  // Affects passengers
        risk: match sigmet.severity.as_str() {
            "SEV" => 0.90,
            "EMBD" => 0.70,
            _ => 0.50,
        },
        economic: 0.40,  // Causes delays
    }
}
