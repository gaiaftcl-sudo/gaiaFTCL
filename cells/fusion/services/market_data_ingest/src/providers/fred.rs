use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// FRED (Federal Reserve Economic Data) API client
pub struct FREDClient {
    client: reqwest::Client,
    api_key: String,
    base_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SeriesObservation {
    pub date: String,
    pub value: String, // Can be "." for missing data
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SeriesResponse {
    pub observations: Vec<SeriesObservation>,
}

impl FREDClient {
    pub fn new(api_key: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
            base_url: "https://api.stlouisfed.org/fred".to_string(),
        }
    }

    /// Get time series data for a FRED series
    pub async fn get_series(&self, series_id: &str) -> Result<Vec<SeriesObservation>> {
        let url = format!("{}/series/observations", self.base_url);

        let resp = self
            .client
            .get(&url)
            .query(&[
                ("series_id", series_id),
                ("api_key", &self.api_key),
                ("file_type", "json"),
            ])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("FRED API error {}: {}", status, text));
        }

        let result: SeriesResponse = resp.json().await?;
        Ok(result.observations)
    }

    /// Get 10-year Treasury rate for a specific date
    pub async fn get_10y_treasury_rate(&self, date: DateTime<Utc>) -> Result<f64> {
        let series = self.get_series("DGS10").await?;
        
        let date_str = date.format("%Y-%m-%d").to_string();
        
        // Find the observation for the specific date or closest before
        let observation = series
            .iter()
            .rev()
            .find(|obs| obs.date <= date_str && obs.value != ".");
        
        if let Some(obs) = observation {
            obs.value
                .parse::<f64>()
                .map_err(|e| anyhow!("Failed to parse rate: {}", e))
        } else {
            // Default to 4% if no data available
            Ok(0.04)
        }
    }

    /// Get latest 10-year Treasury rate
    pub async fn get_latest_10y_treasury_rate(&self) -> Result<f64> {
        let series = self.get_series("DGS10").await?;
        
        // Find the most recent non-missing observation
        let observation = series
            .iter()
            .rev()
            .find(|obs| obs.value != ".");
        
        if let Some(obs) = observation {
            obs.value
                .parse::<f64>()
                .map_err(|e| anyhow!("Failed to parse rate: {}", e))
        } else {
            Ok(0.04) // Default 4%
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fred_client_creation() {
        let client = FREDClient::new("test_key".to_string());
        assert_eq!(client.api_key, "test_key");
    }
}

