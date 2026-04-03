use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DnsRecord {
    pub name: String,
    pub record_type: String,
    pub value: String,
    pub ttl: u32,
}

#[async_trait]
pub trait DnsProvider: Send + Sync {
    async fn get_records(&self, zone: &str, name: &str, record_type: &str) -> Result<Vec<DnsRecord>>;
    async fn upsert_record(&self, zone: &str, name: &str, record_type: &str, value: &str, ttl: u32) -> Result<UpsertResult>;
    fn provider_kind(&self) -> &str;
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpsertResult {
    pub success: bool,
    pub http_status: Option<u16>,
    pub request_id: Option<String>,
    pub error_message: Option<String>,
}
