use anyhow::{anyhow, Context, Result};
use economic_digital_twin::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub mod arango_client;
pub mod bootstrap;

/// Calculate contract entropy from credit rating history
/// Uses rating transitions as proxy for contract uncertainty
pub async fn calculate_contract_entropy(
    tile: &EconomicTile,
    arango: &arango_client::ArangoClient,
) -> Result<f64> {
    let ticker = tile
        .location
        .ticker
        .as_ref()
        .ok_or_else(|| anyhow!("Ticker required for contract entropy calculation"))?;

    // Get rating history from ArangoDB
    let rating_history = get_rating_history(ticker, arango).await?;

    if rating_history.is_empty() {
        // No rating data - use sector average
        return Ok(get_sector_average_contract_entropy(&tile.location.sector_gics));
    }

    // Count rating transitions in past 2 years
    let two_years_ago = tile.timestamp - chrono::Duration::days(730);
    let transitions = count_rating_transitions(&rating_history, two_years_ago);

    // More transitions = higher entropy
    // AAA (no transitions) -> 0.1
    // Frequent downgrades -> 2.5
    let base_entropy = if let Some(latest) = rating_history.last() {
        CreditRating::from_str(&latest.rating)
            .map(|r| r.to_entropy())
            .unwrap_or(1.0)
    } else {
        1.0
    };

    let transition_penalty = 0.3 * (transitions as f64);

    Ok((base_entropy + transition_penalty).min(3.0))
}

/// Calculate information reliability entropy from earnings surprises
/// Uses forecast error distribution as proxy for information quality
pub async fn calculate_info_entropy(
    tile: &EconomicTile,
    arango: &arango_client::ArangoClient,
) -> Result<f64> {
    let ticker = tile
        .location
        .ticker
        .as_ref()
        .ok_or_else(|| anyhow!("Ticker required for info entropy calculation"))?;

    // Get earnings surprises from ArangoDB
    let surprises = get_earnings_surprises(ticker, arango).await?;

    if surprises.len() < 4 {
        // Not enough data - use volatility as proxy
        return calculate_info_entropy_from_volatility(tile, arango).await;
    }

    // Calculate distribution of (actual - expected) / expected
    let surprise_pcts: Vec<f64> = surprises
        .iter()
        .filter(|s| s.expected.abs() > 1e-6)
        .map(|s| (s.actual - s.expected) / s.expected.abs())
        .collect();

    if surprise_pcts.is_empty() {
        return calculate_info_entropy_from_volatility(tile, arango).await;
    }

    // Shannon entropy of discretized distribution
    let bins = discretize(&surprise_pcts, 5); // 5 bins
    Ok(shannon_entropy(&bins))
}

/// Fallback: Calculate info entropy from price volatility
async fn calculate_info_entropy_from_volatility(
    tile: &EconomicTile,
    arango: &arango_client::ArangoClient,
) -> Result<f64> {
    let ticker = tile
        .location
        .ticker
        .as_ref()
        .ok_or_else(|| anyhow!("Ticker required"))?;

    // Get recent prices (90 days)
    let prices = get_recent_prices(ticker, 90, arango).await?;

    if prices.len() < 10 {
        // Not enough data - return default
        return Ok(0.8);
    }

    // Calculate returns
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

    if returns.is_empty() {
        return Ok(0.8);
    }

    let volatility = std_dev(&returns);

    // Map volatility to entropy: 10% vol -> 0.5, 50% vol -> 2.0
    Ok((volatility * 4.0).clamp(0.1, 3.0))
}

/// Calculate rule enforcement entropy from country governance
/// Phase 1: Use country-level governance indices
pub fn calculate_rule_enforcement_entropy(tile: &EconomicTile) -> Result<f64> {
    let country = &tile.location.country_iso;

    // Hardcoded for Phase 1 (US companies)
    // Based on World Bank Governance Indicators: Rule of Law index
    let entropy = match country.as_str() {
        "US" => 0.3,  // Low rule entropy (strong institutions)
        "GB" => 0.3,  // UK - similar to US
        "DE" => 0.25, // Germany - very strong rule of law
        "FR" => 0.35, // France
        "JP" => 0.3,  // Japan
        "CN" => 1.5,  // China - higher entropy (policy uncertainty)
        "RU" => 2.0,  // Russia - high entropy
        "BR" => 1.0,  // Brazil
        "IN" => 0.8,  // India
        _ => 0.5,     // Default
    };

    Ok(entropy)
}

/// Calculate property rights entropy from sector characteristics
/// Phase 1: Use sector-based heuristics
pub fn calculate_property_rights_entropy(tile: &EconomicTile) -> Result<f64> {
    let sector = &tile.location.sector_gics;

    // Some sectors have clearer property rights than others
    let entropy = match sector.as_str() {
        "Financials" => 0.4,        // Clear property rights
        "Utilities" => 0.5,         // Regulated but stable
        "Consumer Staples" => 0.5,  // Stable
        "Health Care" => 0.7,       // Some IP disputes
        "Technology" => 0.8,        // IP disputes common
        "Communication Services" => 0.7,
        "Industrials" => 0.6,
        "Consumer Discretionary" => 0.6,
        "Materials" => 0.7,
        "Energy" => 1.2,            // Regulatory/expropriation risk
        "Real Estate" => 0.6,
        _ => 0.6,                   // Default
    };

    Ok(entropy)
}

/// Calculate composite entropy state from all components
pub async fn calculate_composite_entropy(
    tile: &EconomicTile,
    arango: &arango_client::ArangoClient,
) -> Result<EntropyState> {
    let h_contract = calculate_contract_entropy(tile, arango).await?;
    let h_info = calculate_info_entropy(tile, arango).await?;
    let h_rule = calculate_rule_enforcement_entropy(tile)?;
    let h_property = calculate_property_rights_entropy(tile)?;

    // Weighted composite (equal weights for Phase 1)
    let h_e = 0.25 * h_contract + 0.25 * h_info + 0.25 * h_rule + 0.25 * h_property;

    // Uncertainty: higher if based on sparse data
    let confidence = if tile.source_count > 3 { 0.8 } else { 0.5 };
    let uncertainty = (1.0 - confidence) * h_e;

    Ok(EntropyState {
        contract_entropy: h_contract,
        info_reliability_entropy: h_info,
        rule_enforcement_entropy: h_rule,
        property_rights_entropy: h_property,
        composite_entropy: h_e,
        entropy_externalization: HashMap::new(), // Phase 2
        entropy_uncertainty: uncertainty,
        confidence,
    })
}

// ===== Helper Functions =====

fn get_sector_average_contract_entropy(sector: &str) -> f64 {
    // Sector-based defaults when no rating data available
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

fn count_rating_transitions(history: &[RatingHistory], since: chrono::DateTime<chrono::Utc>) -> usize {
    let mut transitions = 0;
    let mut last_rating: Option<&str> = None;

    for entry in history {
        if entry.date < since {
            continue;
        }

        if let Some(last) = last_rating {
            if last != entry.rating.as_str() {
                transitions += 1;
            }
        }
        last_rating = Some(&entry.rating);
    }

    transitions
}

/// Shannon entropy of a probability distribution
fn shannon_entropy(distribution: &[f64]) -> f64 {
    distribution
        .iter()
        .filter(|&&p| p > 0.0)
        .map(|&p| -p * p.log2())
        .sum()
}

/// Discretize continuous values into bins for entropy calculation
fn discretize(values: &[f64], num_bins: usize) -> Vec<f64> {
    if values.is_empty() {
        return vec![1.0]; // Uniform distribution
    }

    let min = values.iter().cloned().fold(f64::INFINITY, f64::min);
    let max = values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

    if (max - min).abs() < 1e-10 {
        // All values are the same
        return vec![1.0];
    }

    let bin_width = (max - min) / num_bins as f64;

    let mut bins = vec![0.0; num_bins];
    for &v in values {
        let bin_idx = ((v - min) / bin_width).floor() as usize;
        let bin_idx = bin_idx.min(num_bins - 1);
        bins[bin_idx] += 1.0;
    }

    // Normalize to probability distribution
    let total: f64 = bins.iter().sum();
    if total > 0.0 {
        bins.iter().map(|&count| count / total).collect()
    } else {
        vec![1.0 / num_bins as f64; num_bins]
    }
}

/// Calculate standard deviation
fn std_dev(values: &[f64]) -> f64 {
    if values.is_empty() {
        return 0.0;
    }

    let mean: f64 = values.iter().sum::<f64>() / values.len() as f64;
    let variance: f64 = values.iter().map(|&x| (x - mean).powi(2)).sum::<f64>() / values.len() as f64;
    variance.sqrt()
}

// ===== Database Query Functions =====

async fn get_rating_history(
    ticker: &str,
    arango: &arango_client::ArangoClient,
) -> Result<Vec<RatingHistory>> {
    // Query rating history from ArangoDB
    // Returns empty if rating data collection doesn't exist yet
    Ok(vec![])
}

async fn get_earnings_surprises(
    ticker: &str,
    arango: &arango_client::ArangoClient,
) -> Result<Vec<EarningsSurprise>> {
    // Query earnings surprises from ArangoDB
    // Returns empty if earnings collection doesn't exist yet
    Ok(vec![])
}

async fn get_recent_prices(
    ticker: &str,
    days: i64,
    arango: &arango_client::ArangoClient,
) -> Result<Vec<f64>> {
    // Query recent prices from economic_tiles_corporate
    let query = format!(
        r#"
        FOR tile IN economic_tiles_corporate
            FILTER tile.location.ticker == @ticker
            FILTER tile.timestamp > DATE_SUBTRACT(NOW(), {}, 'day')
            SORT tile.timestamp ASC
            RETURN tile.state.observables.equity_price
        "#,
        days
    );

    let result = arango
        .query(&query, serde_json::json!({"ticker": ticker}))
        .await?;

    let prices: Vec<Option<f64>> = serde_json::from_value(result)?;
    Ok(prices.into_iter().flatten().collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shannon_entropy() {
        // Uniform distribution should have maximum entropy
        let uniform = vec![0.25, 0.25, 0.25, 0.25];
        let entropy = shannon_entropy(&uniform);
        assert!((entropy - 2.0).abs() < 0.01); // log2(4) = 2

        // Deterministic distribution should have zero entropy
        let deterministic = vec![1.0, 0.0, 0.0, 0.0];
        let entropy = shannon_entropy(&deterministic);
        assert!(entropy.abs() < 0.01);
    }

    #[test]
    fn test_discretize() {
        let values = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let bins = discretize(&values, 5);
        assert_eq!(bins.len(), 5);
        assert!((bins.iter().sum::<f64>() - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_std_dev() {
        let values = vec![2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];
        let sd = std_dev(&values);
        assert!((sd - 2.0).abs() < 0.1);
    }

    #[test]
    fn test_sector_entropy() {
        assert_eq!(get_sector_average_contract_entropy("Financials"), 0.8);
        assert_eq!(get_sector_average_contract_entropy("Energy"), 1.2);
        assert_eq!(get_sector_average_contract_entropy("Unknown"), 0.7);
    }
}

