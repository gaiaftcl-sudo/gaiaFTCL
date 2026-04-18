use crate::provider::{DnsProvider, DnsRecord, UpsertResult};
use anyhow::{Context, Result};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct GoDaddyProvider {
    api_key: String,
    api_secret: String,
    base_url: String,
    client: reqwest::Client,
}

#[derive(Debug, Serialize, Deserialize)]
struct GoDaddyRecord {
    data: String,
    ttl: u32,
}

impl GoDaddyProvider {
    pub fn new(api_key: String, api_secret: String) -> Self {
        Self {
            api_key,
            api_secret,
            base_url: "https://api.godaddy.com".to_string(),
            client: reqwest::Client::new(),
        }
    }

    fn auth_header(&self) -> String {
        format!("sso-key {}:{}", self.api_key, self.api_secret)
    }

    /// Map FQDN to GoDaddy record name
    /// apex (domain itself) => "@"
    /// subdomain.domain => "subdomain"
    fn map_name(fqdn: &str, zone: &str) -> String {
        if fqdn == zone || fqdn.is_empty() || fqdn == "." {
            "@".to_string()
        } else if let Some(subdomain) = fqdn.strip_suffix(&format!(".{}", zone)) {
            subdomain.to_string()
        } else {
            fqdn.to_string()
        }
    }
}

#[async_trait]
impl DnsProvider for GoDaddyProvider {
    async fn get_records(&self, zone: &str, name: &str, record_type: &str) -> Result<Vec<DnsRecord>> {
        let mapped_name = Self::map_name(name, zone);
        let url = format!(
            "{}/v1/domains/{}/records/{}/{}",
            self.base_url, zone, record_type, mapped_name
        );

        tracing::debug!("GoDaddy GET: {}", url);

        let response = self
            .client
            .get(&url)
            .header("Authorization", self.auth_header())
            .header("Accept", "application/json")
            .send()
            .await
            .context("Failed to send GoDaddy API request")?;

        let status = response.status();
        
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            anyhow::bail!("GoDaddy API error {}: {}", status, error_text);
        }

        let godaddy_records: Vec<GoDaddyRecord> = response
            .json()
            .await
            .context("Failed to parse GoDaddy API response")?;

        Ok(godaddy_records
            .into_iter()
            .map(|r| DnsRecord {
                name: mapped_name.clone(),
                record_type: record_type.to_string(),
                value: r.data,
                ttl: r.ttl,
            })
            .collect())
    }

    async fn upsert_record(&self, zone: &str, name: &str, record_type: &str, value: &str, ttl: u32) -> Result<UpsertResult> {
        let mapped_name = Self::map_name(name, zone);
        let url = format!(
            "{}/v1/domains/{}/records/{}/{}",
            self.base_url, zone, record_type, mapped_name
        );

        let body = vec![GoDaddyRecord {
            data: value.to_string(),
            ttl,
        }];

        tracing::info!("GoDaddy PUT: {} => {} (TTL: {})", url, value, ttl);

        let response = self
            .client
            .put(&url)
            .header("Authorization", self.auth_header())
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .context("Failed to send GoDaddy upsert request")?;

        let status = response.status();
        let request_id = response
            .headers()
            .get("x-request-id")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        if status.is_success() {
            Ok(UpsertResult {
                success: true,
                http_status: Some(status.as_u16()),
                request_id,
                error_message: None,
            })
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            Ok(UpsertResult {
                success: false,
                http_status: Some(status.as_u16()),
                request_id,
                error_message: Some(error_text),
            })
        }
    }

    fn provider_kind(&self) -> &str {
        "godaddy"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apex_name_mapping() {
        assert_eq!(GoDaddyProvider::map_name("gaiaftcl.com", "gaiaftcl.com"), "@");
        assert_eq!(GoDaddyProvider::map_name("", "gaiaftcl.com"), "@");
        assert_eq!(GoDaddyProvider::map_name(".", "gaiaftcl.com"), "@");
    }

    #[test]
    fn test_subdomain_mapping() {
        assert_eq!(
            GoDaddyProvider::map_name("www.gaiaftcl.com", "gaiaftcl.com"),
            "www"
        );
        assert_eq!(
            GoDaddyProvider::map_name("api.gaiaftcl.com", "gaiaftcl.com"),
            "api"
        );
    }
}
