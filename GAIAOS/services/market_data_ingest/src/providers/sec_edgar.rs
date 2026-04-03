use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// SEC EDGAR API client
pub struct SECEdgarClient {
    client: reqwest::Client,
    user_agent: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CompanyFacts {
    pub cik: String,
    #[serde(rename = "entityName")]
    pub entity_name: String,
    pub facts: HashMap<String, HashMap<String, FactData>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FactData {
    pub label: String,
    pub description: String,
    pub units: HashMap<String, Vec<FactValue>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FactValue {
    pub end: String,
    pub val: f64,
    pub accn: String,
    pub fy: Option<i32>,
    pub fp: Option<String>,
    pub form: String,
    pub filed: String,
}

impl SECEdgarClient {
    pub fn new(user_agent: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            user_agent,
        }
    }

    pub fn from_env() -> Self {
        let user_agent = std::env::var("SEC_USER_AGENT")
            .unwrap_or_else(|_| "GaiaOS rick@fortressai.com".to_string());
        Self::new(user_agent)
    }

    /// Get company facts (XBRL data) for a CIK
    pub async fn get_company_facts(&self, cik: &str) -> Result<CompanyFacts> {
        // Pad CIK to 10 digits
        let padded_cik = format!("{:0>10}", cik);
        
        let url = format!(
            "https://data.sec.gov/api/xbrl/companyfacts/CIK{}.json",
            padded_cik
        );

        let resp = self
            .client
            .get(&url)
            .header("User-Agent", &self.user_agent)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("SEC EDGAR API error {}: {}", status, text));
        }

        let result: CompanyFacts = resp.json().await?;
        Ok(result)
    }

    /// Extract balance sheet data from company facts
    pub fn extract_balance_sheet(&self, facts: &CompanyFacts) -> Result<HashMap<String, f64>> {
        let mut data = HashMap::new();

        // Try to extract common balance sheet items
        if let Some(us_gaap) = facts.facts.get("us-gaap") {
            // Assets
            if let Some(assets) = us_gaap.get("Assets") {
                if let Some(usd_units) = assets.units.get("USD") {
                    if let Some(latest) = usd_units.last() {
                        data.insert("total_assets".to_string(), latest.val);
                    }
                }
            }

            // Liabilities
            if let Some(liabilities) = us_gaap.get("Liabilities") {
                if let Some(usd_units) = liabilities.units.get("USD") {
                    if let Some(latest) = usd_units.last() {
                        data.insert("total_liabilities".to_string(), latest.val);
                    }
                }
            }

            // Stockholders Equity
            if let Some(equity) = us_gaap.get("StockholdersEquity") {
                if let Some(usd_units) = equity.units.get("USD") {
                    if let Some(latest) = usd_units.last() {
                        data.insert("equity_book_value".to_string(), latest.val);
                    }
                }
            }

            // Cash
            if let Some(cash) = us_gaap.get("CashAndCashEquivalentsAtCarryingValue") {
                if let Some(usd_units) = cash.units.get("USD") {
                    if let Some(latest) = usd_units.last() {
                        data.insert("cash".to_string(), latest.val);
                    }
                }
            }
        }

        Ok(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sec_client_creation() {
        let client = SECEdgarClient::new("test_agent".to_string());
        assert_eq!(client.user_agent, "test_agent");
    }
}

