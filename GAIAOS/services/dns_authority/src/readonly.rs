use crate::provider::{DnsProvider, DnsRecord, UpsertResult};
use anyhow::Result;
use async_trait::async_trait;

/// Read-only provider that never makes changes
/// Used when secrets are not available
#[derive(Debug, Clone)]
pub struct ReadOnlyProvider;

#[async_trait]
impl DnsProvider for ReadOnlyProvider {
    async fn get_records(&self, _zone: &str, _name: &str, _record_type: &str) -> Result<Vec<DnsRecord>> {
        // Cannot query without credentials
        Ok(vec![])
    }

    async fn upsert_record(&self, _zone: &str, _name: &str, _record_type: &str, _value: &str, _ttl: u32) -> Result<UpsertResult> {
        tracing::warn!("READ_ONLY mode: upsert_record called but no action taken");
        Ok(UpsertResult {
            success: false,
            http_status: None,
            request_id: None,
            error_message: Some("READ_ONLY mode: no credentials".to_string()),
        })
    }

    fn provider_kind(&self) -> &str {
        "readonly"
    }
}
