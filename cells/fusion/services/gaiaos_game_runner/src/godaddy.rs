use serde::{Deserialize, Serialize};
use reqwest::Client;
use std::error::Error;

#[derive(Debug, Serialize, Deserialize)]
pub struct GodaddyRecord {
    pub r#type: String,
    pub name: String,
    pub data: String,
    pub ttl: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub priority: Option<u32>,
}

pub struct GodaddyClient {
    api_key: String,
    api_secret: String,
    domain: String,
    client: Client,
}

impl GodaddyClient {
    pub fn new(api_key: String, api_secret: String, domain: String) -> Self {
        Self {
            api_key,
            api_secret,
            domain,
            client: Client::new(),
        }
    }

    pub async fn push_records(&self, records: Vec<GodaddyRecord>) -> Result<(), Box<dyn Error>> {
        let url = format!("https://api.godaddy.com/v1/domains/{}/records", self.domain);
        let auth = format!("sso-key {}:{}", self.api_key, self.api_secret);

        let resp = self.client.patch(&url)
            .header("Authorization", auth)
            .header("Content-Type", "application/json")
            .json(&records)
            .send()
            .await?;

        if resp.status().is_success() {
            Ok(())
        } else {
            let err_text = resp.text().await?;
            Err(format!("GoDaddy API failed: {}", err_text).into())
        }
    }
}
