use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

/// Financial Modeling Prep API client
pub struct FMPClient {
    client: reqwest::Client,
    api_key: String,
    base_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BalanceSheet {
    pub date: String,
    pub symbol: String,
    #[serde(rename = "totalAssets")]
    pub total_assets: Option<f64>,
    #[serde(rename = "totalDebt")]
    pub total_debt: Option<f64>,
    #[serde(rename = "totalStockholdersEquity")]
    pub total_equity: Option<f64>,
    #[serde(rename = "cashAndCashEquivalents")]
    pub cash: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IncomeStatement {
    pub date: String,
    pub symbol: String,
    pub revenue: Option<f64>,
    #[serde(rename = "ebitda")]
    pub ebitda: Option<f64>,
    #[serde(rename = "netIncome")]
    pub net_income: Option<f64>,
    #[serde(rename = "operatingIncome")]
    pub operating_income: Option<f64>,
    #[serde(rename = "interestExpense")]
    pub interest_expense: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CashFlow {
    pub date: String,
    pub symbol: String,
    #[serde(rename = "freeCashFlow")]
    pub free_cash_flow: Option<f64>,
    #[serde(rename = "capitalExpenditure")]
    pub capital_expenditure: Option<f64>,
    #[serde(rename = "operatingCashFlow")]
    pub operating_cash_flow: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SP500Constituent {
    pub symbol: String,
    pub name: String,
    pub sector: String,
    pub industry: Option<String>,
}

impl FMPClient {
    pub fn new(api_key: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
            base_url: "https://financialmodelingprep.com/api/v3".to_string(),
        }
    }

    /// Get balance sheet data for a ticker
    pub async fn get_balance_sheet(&self, ticker: &str) -> Result<Vec<BalanceSheet>> {
        let url = format!("{}/balance-sheet-statement/{}", self.base_url, ticker);

        let resp = self
            .client
            .get(&url)
            .query(&[("apikey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("FMP API error {}: {}", status, text));
        }

        let result: Vec<BalanceSheet> = resp.json().await?;
        Ok(result)
    }

    /// Get income statement data for a ticker
    pub async fn get_income_statement(&self, ticker: &str) -> Result<Vec<IncomeStatement>> {
        let url = format!("{}/income-statement/{}", self.base_url, ticker);

        let resp = self
            .client
            .get(&url)
            .query(&[("apikey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("FMP API error {}: {}", status, text));
        }

        let result: Vec<IncomeStatement> = resp.json().await?;
        Ok(result)
    }

    /// Get cash flow statement data for a ticker
    pub async fn get_cash_flow(&self, ticker: &str) -> Result<Vec<CashFlow>> {
        let url = format!("{}/cash-flow-statement/{}", self.base_url, ticker);

        let resp = self
            .client
            .get(&url)
            .query(&[("apikey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("FMP API error {}: {}", status, text));
        }

        let result: Vec<CashFlow> = resp.json().await?;
        Ok(result)
    }

    /// Get S&P 500 constituents list
    pub async fn get_sp500_constituents(&self) -> Result<Vec<String>> {
        let url = format!("{}/sp500_constituent", self.base_url);

        let resp = self
            .client
            .get(&url)
            .query(&[("apikey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("FMP API error {}: {}", status, text));
        }

        let result: Vec<SP500Constituent> = resp.json().await?;
        Ok(result.into_iter().map(|c| c.symbol).collect())
    }

    /// Get S&P 500 constituents with sector information
    pub async fn get_sp500_constituents_with_sectors(&self) -> Result<Vec<SP500Constituent>> {
        let url = format!("{}/sp500_constituent", self.base_url);

        let resp = self
            .client
            .get(&url)
            .query(&[("apikey", &self.api_key)])
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("FMP API error {}: {}", status, text));
        }

        let result: Vec<SP500Constituent> = resp.json().await?;
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fmp_client_creation() {
        let client = FMPClient::new("test_key".to_string());
        assert_eq!(client.api_key, "test_key");
    }
}

