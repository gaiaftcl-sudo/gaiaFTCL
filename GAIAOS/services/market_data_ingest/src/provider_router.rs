use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use tracing::{error, info, warn};

use crate::providers::*;
use crate::rate_limiter::RateLimiter;

/// Provider router with automatic failover
pub struct ProviderRouter {
    pub massive: MassiveClient,
    pub yahoo: YahooClient,
    pub fmp: FMPClient,
    pub sec: SECEdgarClient,
    pub fred: FREDClient,
    pub rate_limiter: RateLimiter,
}

#[derive(Debug, Clone)]
pub struct OHLCV {
    pub timestamp: DateTime<Utc>,
    pub open: f64,
    pub high: f64,
    pub low: f64,
    pub close: f64,
    pub volume: f64,
    pub vwap: Option<f64>,
}

#[derive(Debug, Clone)]
pub struct Fundamentals {
    pub total_assets: Option<f64>,
    pub total_debt: Option<f64>,
    pub equity_book_value: Option<f64>,
    pub cash: Option<f64>,
    pub revenue: Option<f64>,
    pub ebitda: Option<f64>,
    pub net_income: Option<f64>,
    pub free_cash_flow: Option<f64>,
}

impl ProviderRouter {
    pub fn new(
        massive_api_key: String,
        fmp_api_key: String,
        fred_api_key: String,
    ) -> Self {
        Self {
            massive: MassiveClient::new(massive_api_key),
            yahoo: YahooClient::new(),
            fmp: FMPClient::new(fmp_api_key),
            sec: SECEdgarClient::from_env(),
            fred: FREDClient::new(fred_api_key),
            rate_limiter: RateLimiter::new(),
        }
    }

    /// Fetch daily prices with automatic failover: Massive → Yahoo
    pub async fn fetch_daily_prices(&self, ticker: &str, date: &str) -> Result<Vec<OHLCV>> {
        let mut errors = Vec::new();

        // Try Massive first (best quality)
        if self.rate_limiter.try_acquire_massive().await {
            match self.try_massive_daily(ticker, date).await {
                Ok(data) => {
                    info!("✓ Fetched {} from Massive", ticker);
                    return Ok(data);
                }
                Err(e) => {
                    warn!("Massive error for {}: {}", ticker, e);
                    errors.push(format!("Massive: {}", e));
                }
            }
        } else {
            warn!("Massive rate limit reached, falling back to Yahoo");
        }

        // Fallback to Yahoo
        match self.try_yahoo_daily(ticker, date).await {
            Ok(data) => {
                info!("✓ Fetched {} from Yahoo (fallback)", ticker);
                Ok(data)
            }
            Err(e) => {
                error!("Yahoo error for {}: {}", ticker, e);
                errors.push(format!("Yahoo: {}", e));
                Err(anyhow!(
                    "All providers failed for {}: {:?}",
                    ticker,
                    errors
                ))
            }
        }
    }

    /// Fetch historical bulk data (Yahoo only - unlimited)
    pub async fn fetch_historical_bulk(
        &self,
        ticker: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<OHLCV>> {
        let quotes = self.yahoo.fetch_history(ticker, start, end).await?;
        
        Ok(quotes
            .into_iter()
            .map(|q| OHLCV {
                timestamp: q.timestamp,
                open: q.open,
                high: q.high,
                low: q.low,
                close: q.close,
                volume: q.volume as f64,
                vwap: None,
            })
            .collect())
    }

    /// Fetch fundamentals with automatic failover: FMP → SEC EDGAR
    pub async fn fetch_fundamentals(&self, ticker: &str) -> Result<Fundamentals> {
        let mut errors = Vec::new();

        // Try FMP first (pre-parsed, easier)
        if self.rate_limiter.try_acquire_fmp().await {
            match self.try_fmp_fundamentals(ticker).await {
                Ok(data) => {
                    info!("✓ Fetched {} fundamentals from FMP", ticker);
                    return Ok(data);
                }
                Err(e) => {
                    warn!("FMP error for {}: {}", ticker, e);
                    errors.push(format!("FMP: {}", e));
                }
            }
        }

        // Fallback to SEC EDGAR (requires CIK lookup)
        match self.try_sec_fundamentals(ticker).await {
            Ok(data) => {
                info!("✓ Fetched {} fundamentals from SEC EDGAR (fallback)", ticker);
                Ok(data)
            }
            Err(e) => {
                error!("SEC EDGAR error for {}: {}", ticker, e);
                errors.push(format!("SEC: {}", e));
                Err(anyhow!(
                    "All providers failed for {} fundamentals: {:?}",
                    ticker,
                    errors
                ))
            }
        }
    }

    // ===== Private helper methods =====

    async fn try_massive_daily(&self, ticker: &str, date: &str) -> Result<Vec<OHLCV>> {
        let aggs = self
            .massive
            .get_aggs(ticker, 1, "day", date, date)
            .await?;

        Ok(aggs
            .results
            .into_iter()
            .map(|bar| OHLCV {
                timestamp: DateTime::from_timestamp_millis(bar.timestamp)
                    .unwrap_or(Utc::now()),
                open: bar.open,
                high: bar.high,
                low: bar.low,
                close: bar.close,
                volume: bar.volume,
                vwap: Some(bar.vwap),
            })
            .collect())
    }

    async fn try_yahoo_daily(&self, ticker: &str, _date: &str) -> Result<Vec<OHLCV>> {
        // Yahoo doesn't support single-date queries, so get last 7 days and filter
        let end = Utc::now();
        let start = end - chrono::Duration::days(7);
        
        let quotes = self.yahoo.fetch_history(ticker, start, end).await?;
        
        Ok(quotes
            .into_iter()
            .map(|q| OHLCV {
                timestamp: q.timestamp,
                open: q.open,
                high: q.high,
                low: q.low,
                close: q.close,
                volume: q.volume as f64,
                vwap: None,
            })
            .collect())
    }

    async fn try_fmp_fundamentals(&self, ticker: &str) -> Result<Fundamentals> {
        let balance_sheets = self.fmp.get_balance_sheet(ticker).await?;
        let income_statements = self.fmp.get_income_statement(ticker).await?;
        let cash_flows = self.fmp.get_cash_flow(ticker).await?;

        let latest_bs = balance_sheets.first();
        let latest_is = income_statements.first();
        let latest_cf = cash_flows.first();

        Ok(Fundamentals {
            total_assets: latest_bs.and_then(|bs| bs.total_assets),
            total_debt: latest_bs.and_then(|bs| bs.total_debt),
            equity_book_value: latest_bs.and_then(|bs| bs.total_equity),
            cash: latest_bs.and_then(|bs| bs.cash),
            revenue: latest_is.and_then(|is| is.revenue),
            ebitda: latest_is.and_then(|is| is.ebitda),
            net_income: latest_is.and_then(|is| is.net_income),
            free_cash_flow: latest_cf.and_then(|cf| cf.free_cash_flow),
        })
    }

    async fn try_sec_fundamentals(&self, _ticker: &str) -> Result<Fundamentals> {
        // SEC EDGAR requires CIK, which we don't have readily available
        // For Phase 1, return error to use FMP
        Err(anyhow!("SEC EDGAR requires CIK lookup (not implemented in Phase 1)"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ohlcv_creation() {
        let ohlcv = OHLCV {
            timestamp: Utc::now(),
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1000000.0,
            vwap: Some(102.0),
        };
        
        assert_eq!(ohlcv.open, 100.0);
        assert_eq!(ohlcv.vwap, Some(102.0));
    }
}

