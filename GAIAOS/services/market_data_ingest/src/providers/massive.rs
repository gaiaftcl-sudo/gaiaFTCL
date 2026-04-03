use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Massive.com (Polygon.io) API client
pub struct MassiveClient {
    client: reqwest::Client,
    api_key: String,
    base_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AggsResponse {
    pub ticker: String,
    pub results: Vec<AggBar>,
    pub status: String,
    pub count: Option<usize>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AggBar {
    #[serde(rename = "t")]
    pub timestamp: i64, // Unix timestamp in milliseconds
    #[serde(rename = "o")]
    pub open: f64,
    #[serde(rename = "h")]
    pub high: f64,
    #[serde(rename = "l")]
    pub low: f64,
    #[serde(rename = "c")]
    pub close: f64,
    #[serde(rename = "v")]
    pub volume: f64,
    #[serde(rename = "vw")]
    pub vwap: f64, // Volume weighted average price
    #[serde(rename = "n")]
    pub transactions: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TickerDetails {
    pub ticker: String,
    pub name: String,
    pub market: Option<String>,
    pub locale: Option<String>,
    pub primary_exchange: Option<String>,
    pub market_cap: Option<f64>,
    pub share_class_shares_outstanding: Option<f64>,
    pub sic_description: Option<String>, // Sector
    pub cik: Option<String>,
    pub cusip: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TickerDetailsResponse {
    pub status: String,
    pub results: TickerDetails,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Dividend {
    pub ex_dividend_date: String,
    pub payment_date: Option<String>,
    pub cash_amount: f64,
    pub declaration_date: Option<String>,
    pub dividend_type: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DividendsResponse {
    pub status: String,
    pub results: Vec<Dividend>,
}

impl MassiveClient {
    pub fn new(api_key: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
            base_url: "https://api.polygon.io".to_string(),
        }
    }

    /// Get aggregated bars (OHLCV) for a ticker
    /// timespan: "minute", "hour", "day", "week", "month", "quarter", "year"
    pub async fn get_aggs(
        &self,
        ticker: &str,
        multiplier: u32,
        timespan: &str,
        from: &str,
        to: &str,
    ) -> Result<AggsResponse> {
        let url = format!(
            "{}/v2/aggs/ticker/{}/range/{}/{}/{}/{}",
            self.base_url, ticker, multiplier, timespan, from, to
        );

        let resp = self
            .client
            .get(&url)
            .query(&[("apiKey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Massive API error {}: {}", status, text));
        }

        let result: AggsResponse = resp.json().await?;
        
        if result.status != "OK" {
            return Err(anyhow!("Massive API returned status: {}", result.status));
        }

        Ok(result)
    }

    /// Get ticker details (company info, sector, market cap, etc.)
    pub async fn get_ticker_details(&self, ticker: &str) -> Result<TickerDetails> {
        let url = format!("{}/v3/reference/tickers/{}", self.base_url, ticker);

        let resp = self
            .client
            .get(&url)
            .query(&[("apiKey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Massive API error {}: {}", status, text));
        }

        let result: TickerDetailsResponse = resp.json().await?;
        
        if result.status != "OK" {
            return Err(anyhow!("Massive API returned status: {}", result.status));
        }

        Ok(result.results)
    }

    /// Get dividend history for a ticker
    pub async fn get_dividends(&self, ticker: &str) -> Result<Vec<Dividend>> {
        let url = format!("{}/v3/reference/dividends", self.base_url);

        let resp = self
            .client
            .get(&url)
            .query(&[
                ("ticker", ticker),
                ("apiKey", &self.api_key),
            ])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Massive API error {}: {}", status, text));
        }

        let result: DividendsResponse = resp.json().await?;
        
        if result.status != "OK" {
            return Err(anyhow!("Massive API returned status: {}", result.status));
        }

        Ok(result.results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_massive_client_creation() {
        let client = MassiveClient::new("test_key".to_string());
        assert_eq!(client.api_key, "test_key");
        assert_eq!(client.base_url, "https://api.polygon.io");
    }
}

