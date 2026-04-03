use anyhow::Result;
use chrono::{DateTime, Utc};
use yahoo_finance_api as yahoo;

/// Yahoo Finance client for bulk historical data
pub struct YahooClient {
    provider: yahoo::YahooConnector,
}

#[derive(Debug, Clone)]
pub struct Quote {
    pub timestamp: DateTime<Utc>,
    pub open: f64,
    pub high: f64,
    pub low: f64,
    pub close: f64,
    pub volume: u64,
}

impl YahooClient {
    pub fn new() -> Self {
        Self {
            provider: yahoo::YahooConnector::new(),
        }
    }

    /// Fetch historical quotes for a ticker
    pub async fn fetch_history(
        &self,
        ticker: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<Quote>> {
        let response = self
            .provider
            .get_quote_history(ticker, start, end)
            .await?;

        let quotes = response
            .quotes()?
            .iter()
            .map(|q| Quote {
                timestamp: DateTime::from_timestamp(q.timestamp as i64, 0)
                    .unwrap_or(Utc::now()),
                open: q.open,
                high: q.high,
                low: q.low,
                close: q.close,
                volume: q.volume,
            })
            .collect();

        Ok(quotes)
    }

    /// Fetch the latest quote for a ticker
    pub async fn fetch_latest(&self, ticker: &str) -> Result<Quote> {
        let end = Utc::now();
        let start = end - chrono::Duration::days(7); // Get last week to ensure we have data

        let quotes = self.fetch_history(ticker, start, end).await?;
        
        quotes
            .into_iter()
            .last()
            .ok_or_else(|| anyhow::anyhow!("No quotes available for {}", ticker))
    }
}

impl Default for YahooClient {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_yahoo_client_creation() {
        let _client = YahooClient::new();
    }
}

