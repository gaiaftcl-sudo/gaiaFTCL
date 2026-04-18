use serde::{Deserialize, Serialize};
use reqwest::Client;
use std::error::Error;

#[derive(Debug, Serialize, Deserialize)]
struct PrimaryIpResponse {
    primary_ips: Vec<PrimaryIp>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PrimaryIp {
    id: u64,
    ip: String,
    dns_ptr: Vec<DnsPtr>,
}

#[derive(Debug, Serialize, Deserialize)]
struct DnsPtr {
    ip: String,
    dns_ptr: String,
}

pub struct HcloudClient {
    token: String,
    client: Client,
}

impl HcloudClient {
    pub fn new(token: String) -> Self {
        Self {
            token,
            client: Client::new(),
        }
    }

    pub async fn set_ptr(&self, ip_addr: &str, hostname: &str) -> Result<(), Box<dyn Error>> {
        // 1. Find the Primary IP ID for the given IP address
        let url = "https://api.hetzner.cloud/v1/primary_ips";
        let resp = self.client.get(url)
            .bearer_auth(&self.token)
            .send()
            .await?;

        let data: PrimaryIpResponse = resp.json().await?;
        let primary_ip = data.primary_ips.into_iter().find(|p| p.ip == ip_addr)
            .ok_or_else(|| format!("Primary IP {} not found in Hetzner", ip_addr))?;

        // 2. Set the PTR record
        let ptr_url = format!("https://api.hetzner.cloud/v1/primary_ips/{}/actions/change_dns_ptr", primary_ip.id);
        let payload = serde_json::json!({
            "dns_ptr": hostname,
            "ip": ip_addr,
        });

        let ptr_resp = self.client.post(&ptr_url)
            .bearer_auth(&self.token)
            .json(&payload)
            .send()
            .await?;

        if ptr_resp.status().is_success() {
            Ok(())
        } else {
            let err_text = ptr_resp.text().await?;
            Err(format!("Hetzner API failed: {}", err_text).into())
        }
    }
}
