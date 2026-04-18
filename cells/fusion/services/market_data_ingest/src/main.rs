mod providers;
mod rate_limiter;
mod provider_router;

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use economic_digital_twin::*;
use entropy_calculation::arango_client::ArangoClient;
use provider_router::{ProviderRouter, OHLCV};
use tracing::{error, info};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    info!("🚀 Starting GaiaOS Market Data Ingestion Service");

    // Initialize provider router
    let massive_key = std::env::var("MASSIVE_API_KEY")
        .context("MASSIVE_API_KEY not set")?;
    let fmp_key = std::env::var("FMP_API_KEY")
        .context("FMP_API_KEY not set")?;
    let fred_key = std::env::var("FRED_API_KEY")
        .context("FRED_API_KEY not set")?;

    let router = ProviderRouter::new(massive_key, fmp_key, fred_key);

    // Initialize ArangoDB client
    let arango = ArangoClient::from_env()?;

    // Check if we need historical load
    if needs_historical_load(&arango).await? {
        info!("📊 Starting bulk historical load (2 years)");
        bulk_historical_load(&router, &arango).await?;
    } else {
        info!("✓ Historical data already loaded");
    }

    // Run daily update
    info!("📈 Starting daily update");
    daily_update(&router, &arango).await?;

    info!("✅ Market data ingestion complete");
    Ok(())
}

/// Check if historical data needs to be loaded
async fn needs_historical_load(arango: &ArangoClient) -> Result<bool> {
    let query = r#"
        RETURN LENGTH(economic_tiles_corporate)
    "#;

    let result = arango
        .query(query, serde_json::json!({}))
        .await?;

    let count: Vec<u64> = serde_json::from_value(result)?;
    let count = count.first().copied().unwrap_or(0);

    info!("Current economic tiles count: {}", count);
    Ok(count < 100) // If less than 100 tiles, assume we need historical load
}

/// Bulk historical load using Yahoo Finance (unlimited)
async fn bulk_historical_load(router: &ProviderRouter, arango: &ArangoClient) -> Result<()> {
    // Get S&P 500 tickers
    info!("Fetching S&P 500 constituents...");
    router.rate_limiter.acquire_fmp().await;
    let tickers = router.fmp.get_sp500_constituents().await?;
    info!("✓ Found {} tickers", tickers.len());

    let start = Utc::now() - chrono::Duration::days(730); // 2 years
    let end = Utc::now();

    info!("Loading historical data from {} to {}", start.format("%Y-%m-%d"), end.format("%Y-%m-%d"));

    let mut success_count = 0;
    let mut error_count = 0;

    for (idx, ticker) in tickers.iter().enumerate() {
        if idx % 50 == 0 {
            info!("Progress: {}/{} tickers", idx, tickers.len());
        }

        match load_ticker_history(router, arango, ticker, start, end).await {
            Ok(count) => {
                info!("✓ Loaded {} bars for {}", count, ticker);
                success_count += 1;
            }
            Err(e) => {
                error!("✗ Failed to load {}: {}", ticker, e);
                error_count += 1;
            }
        }

        // Small delay to be respectful to APIs
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }

    info!(
        "Bulk load complete: {} success, {} errors",
        success_count, error_count
    );

    Ok(())
}

/// Load historical data for a single ticker
async fn load_ticker_history(
    router: &ProviderRouter,
    arango: &ArangoClient,
    ticker: &str,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> Result<usize> {
    let quotes = router.fetch_historical_bulk(ticker, start, end).await?;

    let mut count = 0;
    for quote in quotes {
        let tile = create_equity_tile(ticker, &quote)?;
        arango
            .upsert_document("economic_tiles_corporate", &serde_json::to_value(&tile)?)
            .await?;
        count += 1;
    }

    Ok(count)
}

/// Daily update using Massive (rate limited) with Yahoo fallback
async fn daily_update(router: &ProviderRouter, arango: &ArangoClient) -> Result<()> {
    // Get S&P 500 tickers
    info!("Fetching S&P 500 constituents...");
    router.rate_limiter.acquire_fmp().await;
    let tickers = router.fmp.get_sp500_constituents().await?;
    info!("✓ Found {} tickers", tickers.len());

    let yesterday = (Utc::now() - chrono::Duration::days(1)).format("%Y-%m-%d").to_string();

    let mut success_count = 0;
    let mut error_count = 0;

    for (idx, ticker) in tickers.iter().enumerate() {
        if idx % 50 == 0 {
            info!("Progress: {}/{} tickers", idx, tickers.len());
        }

        match router.fetch_daily_prices(ticker, &yesterday).await {
            Ok(prices) => {
                for price in prices {
                    let tile = create_equity_tile(ticker, &price)?;
                    arango
                        .upsert_document("economic_tiles_corporate", &serde_json::to_value(&tile)?)
                        .await?;
                }
                success_count += 1;
            }
            Err(e) => {
                error!("✗ Failed to fetch {}: {}", ticker, e);
                error_count += 1;
            }
        }
    }

    info!(
        "Daily update complete: {} success, {} errors",
        success_count, error_count
    );

    Ok(())
}

/// Create an economic tile from OHLCV data
fn create_equity_tile(ticker: &str, ohlcv: &OHLCV) -> Result<EconomicTile> {
    Ok(EconomicTile {
        tile_id: format!("equity_{}_{}", ticker, ohlcv.timestamp.timestamp_millis()),
        scale: EconomicScale::Corporate,
        location: EconomicLocation {
            country_iso: "US".to_string(),
            sector_gics: String::new(), // Will be filled by fundamentals
            industry_gics: String::new(),
            ticker: Some(ticker.to_string()),
            cusip: None,
            counterparty_graph_id: ticker.to_string(),
        },
        timestamp: ohlcv.timestamp,
        state: StateVector {
            observables: Observables {
                equity_price: Some(ohlcv.close),
                equity_volume: Some(ohlcv.volume),
                equity_open: Some(ohlcv.open),
                equity_high: Some(ohlcv.high),
                equity_low: Some(ohlcv.low),
                equity_vwap: ohlcv.vwap,
                ..Default::default()
            },
            entropy_state: EntropyState::default(), // Will be calculated later
            network_position: NetworkPosition::default(),
        },
        data_quality: 0.95,
        last_updated: Utc::now(),
        source_count: 1,
    })
}

