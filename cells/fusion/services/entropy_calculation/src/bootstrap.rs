use anyhow::{anyhow, Result};
use economic_digital_twin::*;
use std::collections::HashMap;

use crate::arango_client::ArangoClient;
use crate::{calculate_info_entropy_from_volatility, calculate_property_rights_entropy, calculate_rule_enforcement_entropy};

/// Bootstrap initial entropy state for a tile at t=0
/// Uses two methods: early observables (preferred) or credit rating fallback
pub async fn bootstrap_initial_entropy(
    tile: &EconomicTile,
    arango: &ArangoClient,
) -> Result<EntropyState> {
    let ticker = tile
        .location
        .ticker
        .as_ref()
        .ok_or_else(|| anyhow!("Ticker required for bootstrap"))?;

    // Method 1: Use first 90 days of observables
    let early_tiles = get_early_tiles(ticker, tile.timestamp, arango).await?;

    if early_tiles.len() >= 30 {
        // Enough data to calculate entropy from early observables
        return bootstrap_from_early_data(tile, &early_tiles, arango).await;
    }

    // Method 2: Fallback to credit rating
    bootstrap_from_credit_rating(tile, arango).await
}

/// Bootstrap from early observables (preferred method)
async fn bootstrap_from_early_data(
    tile: &EconomicTile,
    early_tiles: &[EconomicTile],
    arango: &ArangoClient,
) -> Result<EntropyState> {
    // Calculate info entropy from early price volatility
    let prices: Vec<f64> = early_tiles
        .iter()
        .filter_map(|t| t.state.observables.equity_price)
        .collect();

    let h_info = if prices.len() >= 10 {
        let returns: Vec<f64> = prices
            .windows(2)
            .filter_map(|w| {
                if w[0] > 0.0 {
                    Some((w[1] / w[0]).ln())
                } else {
                    None
                }
            })
            .collect();

        if !returns.is_empty() {
            let volatility = std_dev(&returns);
            (volatility * 4.0).clamp(0.1, 3.0)
        } else {
            0.8
        }
    } else {
        0.8
    };

    // Get initial credit rating entropy
    let h_contract = get_initial_credit_rating_entropy(tile, arango).await?;

    // Calculate rule and property entropy (static for Phase 1)
    let h_rule = calculate_rule_enforcement_entropy(tile)?;
    let h_property = calculate_property_rights_entropy(tile)?;

    // Composite entropy
    let h_e = 0.25 * h_contract + 0.25 * h_info + 0.25 * h_rule + 0.25 * h_property;

    Ok(EntropyState {
        composite_entropy: h_e,
        contract_entropy: h_contract,
        info_reliability_entropy: h_info,
        rule_enforcement_entropy: h_rule,
        property_rights_entropy: h_property,
        entropy_uncertainty: 0.5, // High uncertainty at t=0
        confidence: 0.5,
        entropy_externalization: HashMap::new(),
    })
}

/// Bootstrap from credit rating (fallback method)
async fn bootstrap_from_credit_rating(
    tile: &EconomicTile,
    arango: &ArangoClient,
) -> Result<EntropyState> {
    let ticker = tile
        .location
        .ticker
        .as_ref()
        .ok_or_else(|| anyhow!("Ticker required"))?;

    // Try to get credit rating
    let rating = get_initial_credit_rating(ticker, tile.timestamp, arango).await;

    let h_contract = if let Ok(rating_str) = rating {
        CreditRating::from_str(&rating_str)
            .map(|r| r.to_entropy())
            .unwrap_or(1.0)
    } else {
        // No rating data - use sector default
        get_sector_default_entropy(&tile.location.sector_gics)
    };

    // Assume info entropy correlated with credit entropy
    let h_info = h_contract * 0.8;

    // Calculate rule and property entropy
    let h_rule = calculate_rule_enforcement_entropy(tile)?;
    let h_property = calculate_property_rights_entropy(tile)?;

    // Composite entropy
    let h_e = 0.25 * h_contract + 0.25 * h_info + 0.25 * h_rule + 0.25 * h_property;

    Ok(EntropyState {
        composite_entropy: h_e,
        contract_entropy: h_contract,
        info_reliability_entropy: h_info,
        rule_enforcement_entropy: h_rule,
        property_rights_entropy: h_property,
        entropy_uncertainty: 0.7, // Very high uncertainty (sparse data)
        confidence: 0.3,
        entropy_externalization: HashMap::new(),
    })
}

// ===== Helper Functions =====

async fn get_early_tiles(
    ticker: &str,
    start_date: chrono::DateTime<chrono::Utc>,
    arango: &ArangoClient,
) -> Result<Vec<EconomicTile>> {
    let start_ms = start_date.timestamp_millis();
    let end_ms = start_ms + 7776000000; // 90 days in milliseconds

    let query = format!(
        r#"
        FOR t IN economic_tiles_corporate
            FILTER t.location.ticker == @ticker
            FILTER t.timestamp >= {}
            FILTER t.timestamp < {}
            SORT t.timestamp ASC
            RETURN t
        "#,
        start_ms, end_ms
    );

    let result = arango
        .query(&query, serde_json::json!({"ticker": ticker}))
        .await?;

    let tiles: Vec<EconomicTile> = serde_json::from_value(result)?;
    Ok(tiles)
}

async fn get_initial_credit_rating_entropy(
    tile: &EconomicTile,
    _arango: &ArangoClient,
) -> Result<f64> {
    // For Phase 1, use sector default if no rating data
    // TODO: Query actual rating data once available
    Ok(get_sector_default_entropy(&tile.location.sector_gics))
}

async fn get_initial_credit_rating(
    _ticker: &str,
    _timestamp: chrono::DateTime<chrono::Utc>,
    _arango: &ArangoClient,
) -> Result<String> {
    // For Phase 1, return error to trigger fallback
    // TODO: Query actual rating data once available
    Err(anyhow!("No rating data available"))
}

fn get_sector_default_entropy(sector: &str) -> f64 {
    match sector {
        "Financials" => 0.8,
        "Energy" => 1.2,
        "Technology" => 0.6,
        "Health Care" => 0.5,
        "Utilities" => 0.4,
        "Consumer Staples" => 0.5,
        "Industrials" => 0.7,
        "Materials" => 0.9,
        "Consumer Discretionary" => 0.8,
        "Communication Services" => 0.7,
        "Real Estate" => 0.9,
        _ => 0.7,
    }
}

fn std_dev(values: &[f64]) -> f64 {
    if values.is_empty() {
        return 0.0;
    }

    let mean: f64 = values.iter().sum::<f64>() / values.len() as f64;
    let variance: f64 = values.iter().map(|&x| (x - mean).powi(2)).sum::<f64>() / values.len() as f64;
    variance.sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sector_defaults() {
        assert_eq!(get_sector_default_entropy("Financials"), 0.8);
        assert_eq!(get_sector_default_entropy("Energy"), 1.2);
        assert_eq!(get_sector_default_entropy("Unknown"), 0.7);
    }
}

