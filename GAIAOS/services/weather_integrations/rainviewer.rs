/*!
 * RainViewer API Integration
 * 
 * FREE global radar imagery, no API key required
 * Updates every 10 minutes
 */

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct RainViewerResponse {
    pub version: String,
    pub generated: i64,
    pub host: String,
    pub radar: RadarData,
    pub satellite: SatelliteData,
}

#[derive(Debug, Deserialize)]
pub struct RadarData {
    pub past: Vec<RadarFrame>,
    pub nowcast: Vec<RadarFrame>,
}

#[derive(Debug, Deserialize)]
pub struct RadarFrame {
    pub time: i64,
    pub path: String,  // URL path to tile
}

#[derive(Debug, Deserialize)]
pub struct SatelliteData {
    pub infrared: Vec<SatelliteFrame>,
}

#[derive(Debug, Deserialize)]
pub struct SatelliteFrame {
    pub time: i64,
    pub path: String,
}

pub struct RainViewerClient {
    base_url: String,
    http_client: reqwest::Client,
}

impl RainViewerClient {
    pub fn new() -> Self {
        Self {
            base_url: "https://api.rainviewer.com/public/weather-maps.json".to_string(),
            http_client: reqwest::Client::new(),
        }
    }
    
    /// Fetch latest radar frames
    pub async fn fetch_latest(&self) -> Result<RainViewerResponse, Box<dyn std::error::Error>> {
        let response = self.http_client
            .get(&self.base_url)
            .send()
            .await?
            .json::<RainViewerResponse>()
            .await?;
        
        Ok(response)
    }
    
    /// Get tile URL for specific time and coordinates
    /// Tiles use Web Mercator projection (EPSG:3857)
    /// Format: {host}/{path}/{size}/{z}/{x}/{y}/{color}/{options}.png
    pub fn get_tile_url(
        &self,
        host: &str,
        path: &str,
        z: u8,  // zoom level (0-12)
        x: u32,  // tile x
        y: u32,  // tile y
    ) -> String {
        format!(
            "https://{}/{}/256/{}/{}/{}/1/1_1.png",
            host, path, z, x, y
        )
    }
    
    /// Stream radar updates (poll every 10 minutes)
    pub async fn stream_radar_updates(
        &self,
        callback: impl Fn(RadarFrame) -> (),
    ) -> Result<(), Box<dyn std::error::Error>> {
        loop {
            let data = self.fetch_latest().await?;
            
            // Get most recent radar frame
            if let Some(latest) = data.radar.nowcast.last() {
                callback(latest.clone());
            }
            
            // Wait 10 minutes (RainViewer update interval)
            tokio::time::sleep(tokio::time::Duration::from_secs(600)).await;
        }
    }
}

/// Convert lat/lon to tile coordinates at given zoom level
pub fn latlon_to_tile(lat: f64, lon: f64, zoom: u8) -> (u32, u32) {
    let n = 2_u32.pow(zoom as u32) as f64;
    
    let x = ((lon + 180.0) / 360.0 * n) as u32;
    let y = ((1.0 - (lat.to_radians().tan() + 1.0 / lat.to_radians().cos()).ln() / std::f64::consts::PI) / 2.0 * n) as u32;
    
    (x, y)
}
