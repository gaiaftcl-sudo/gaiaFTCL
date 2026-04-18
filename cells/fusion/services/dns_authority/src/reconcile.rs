use crate::provider::{DnsProvider, UpsertResult};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use trust_dns_resolver::config::*;
use trust_dns_resolver::TokioAsyncResolver;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DesiredRecord {
    pub domain: String,
    #[serde(rename = "type")]
    pub record_type: String,
    pub name: String,
    pub value: String,
    pub ttl: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObservedRecord {
    pub resolver: String,
    pub values: Vec<String>,
    pub match_desired: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderAction {
    pub kind: String,
    pub action: String,
    pub http_status: Option<u16>,
    pub request_id: Option<String>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ReconcileStatus {
    #[serde(rename = "VALID")]
    Valid,
    #[serde(rename = "DRIFT")]
    Drift,
    #[serde(rename = "ERROR")]
    Error,
    #[serde(rename = "READ_ONLY")]
    ReadOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CycleEvidence {
    pub cycle_id: String,
    pub ts_start: String,
    pub ts_end: String,
    pub desired: DesiredRecord,
    pub observed: Vec<ObservedRecord>,
    pub provider: ProviderAction,
    pub status: ReconcileStatus,
    pub consecutive_failures: u32,
    pub reason_codes: Vec<String>,
    pub self_hash_sha256: String,
}

impl CycleEvidence {
    pub fn compute_hash(&self) -> String {
        let mut evidence_for_hash = self.clone();
        evidence_for_hash.self_hash_sha256 = String::new();

        let canonical = serde_json::to_string(&evidence_for_hash).unwrap();
        let mut hasher = Sha256::new();
        hasher.update(canonical.as_bytes());
        format!("sha256:{:x}", hasher.finalize())
    }
}

pub struct Reconciler {
    provider: Arc<dyn DnsProvider>,
    domain: String,
    ttl: u32,
    head_public_ip: Option<String>,
    consecutive_failures: u32,
}

impl Reconciler {
    pub fn new(
        provider: Arc<dyn DnsProvider>,
        domain: String,
        ttl: u32,
        head_public_ip: Option<String>,
    ) -> Self {
        Self {
            provider,
            domain,
            ttl,
            head_public_ip,
            consecutive_failures: 0,
        }
    }

    pub async fn reconcile(&mut self) -> Result<CycleEvidence> {
        let cycle_id = uuid::Uuid::new_v4().to_string();
        let ts_start = chrono::Utc::now().to_rfc3339();

        let mut reason_codes = Vec::new();

        // Check if we have HEAD_PUBLIC_IP
        let desired_ip = match &self.head_public_ip {
            Some(ip) => ip.clone(),
            None => {
                reason_codes.push("MISSING_HEAD_PUBLIC_IP".to_string());
                let ts_end = chrono::Utc::now().to_rfc3339();
                
                let mut evidence = CycleEvidence {
                    cycle_id,
                    ts_start,
                    ts_end,
                    desired: DesiredRecord {
                        domain: self.domain.clone(),
                        record_type: "A".to_string(),
                        name: "@".to_string(),
                        value: "UNKNOWN".to_string(),
                        ttl: self.ttl,
                    },
                    observed: vec![],
                    provider: ProviderAction {
                        kind: self.provider.provider_kind().to_string(),
                        action: "none".to_string(),
                        http_status: None,
                        request_id: None,
                        error_message: Some("Missing HEAD_PUBLIC_IP".to_string()),
                    },
                    status: ReconcileStatus::ReadOnly,
                    consecutive_failures: self.consecutive_failures,
                    reason_codes,
                    self_hash_sha256: String::new(),
                };
                
                evidence.self_hash_sha256 = evidence.compute_hash();
                return Ok(evidence);
            }
        };

        let desired = DesiredRecord {
            domain: self.domain.clone(),
            record_type: "A".to_string(),
            name: "@".to_string(),
            value: desired_ip.clone(),
            ttl: self.ttl,
        };

        // Query multiple resolvers
        let observed = self.query_resolvers(&self.domain, &desired_ip).await?;

        // Check for drift
        let has_drift = observed.iter().any(|obs| !obs.match_desired);

        let mut provider_action = ProviderAction {
            kind: self.provider.provider_kind().to_string(),
            action: "none".to_string(),
            http_status: None,
            request_id: None,
            error_message: None,
        };

        let status = if self.provider.provider_kind() == "readonly" {
            if has_drift {
                reason_codes.push("DRIFT_DETECTED_READ_ONLY".to_string());
            }
            ReconcileStatus::ReadOnly
        } else if has_drift {
            // Attempt to reconcile
            reason_codes.push("DRIFT_DETECTED".to_string());
            
            match self.provider.upsert_record(&self.domain, "@", "A", &desired_ip, self.ttl).await {
                Ok(result) => {
                    provider_action.action = "upsert".to_string();
                    provider_action.http_status = result.http_status;
                    provider_action.request_id = result.request_id;
                    provider_action.error_message = result.error_message.clone();

                    if result.success {
                        reason_codes.push("UPSERT_SUCCESS".to_string());
                        self.consecutive_failures = 0;
                        
                        // Wait briefly and re-check
                        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                        
                        ReconcileStatus::Drift
                    } else {
                        reason_codes.push("UPSERT_FAILED".to_string());
                        self.consecutive_failures += 1;
                        ReconcileStatus::Error
                    }
                }
                Err(e) => {
                    reason_codes.push("UPSERT_ERROR".to_string());
                    provider_action.action = "upsert_error".to_string();
                    provider_action.error_message = Some(e.to_string());
                    self.consecutive_failures += 1;
                    ReconcileStatus::Error
                }
            }
        } else {
            self.consecutive_failures = 0;
            ReconcileStatus::Valid
        };

        let ts_end = chrono::Utc::now().to_rfc3339();

        let mut evidence = CycleEvidence {
            cycle_id,
            ts_start,
            ts_end,
            desired,
            observed,
            provider: provider_action,
            status,
            consecutive_failures: self.consecutive_failures,
            reason_codes,
            self_hash_sha256: String::new(),
        };

        evidence.self_hash_sha256 = evidence.compute_hash();
        Ok(evidence)
    }

    async fn query_resolvers(&self, domain: &str, expected_ip: &str) -> Result<Vec<ObservedRecord>> {
        let mut results = Vec::new();

        // System resolver
        let resolver = TokioAsyncResolver::tokio(ResolverConfig::default(), ResolverOpts::default());
        results.push(self.query_resolver("system", &resolver, domain, expected_ip).await);

        // Cloudflare (1.1.1.1)
        let cloudflare_config = ResolverConfig::from_parts(
            None,
            vec![],
            NameServerConfigGroup::from_ips_clear(&[std::net::IpAddr::V4(std::net::Ipv4Addr::new(1, 1, 1, 1))], 53, true),
        );
        let resolver = TokioAsyncResolver::tokio(cloudflare_config, ResolverOpts::default());
        results.push(self.query_resolver("1.1.1.1", &resolver, domain, expected_ip).await);

        // Google (8.8.8.8)
        let google_config = ResolverConfig::from_parts(
            None,
            vec![],
            NameServerConfigGroup::from_ips_clear(&[std::net::IpAddr::V4(std::net::Ipv4Addr::new(8, 8, 8, 8))], 53, true),
        );
        let resolver = TokioAsyncResolver::tokio(google_config, ResolverOpts::default());
        results.push(self.query_resolver("8.8.8.8", &resolver, domain, expected_ip).await);

        Ok(results)
    }

    async fn query_resolver(
        &self,
        resolver_name: &str,
        resolver: &TokioAsyncResolver,
        domain: &str,
        expected_ip: &str,
    ) -> ObservedRecord {
        match resolver.lookup_ip(domain).await {
            Ok(response) => {
                let values: Vec<String> = response.iter().map(|ip| ip.to_string()).collect();
                let match_desired = values.contains(&expected_ip.to_string());
                
                ObservedRecord {
                    resolver: resolver_name.to_string(),
                    values,
                    match_desired,
                }
            }
            Err(e) => {
                tracing::warn!("DNS query failed for {} via {}: {}", domain, resolver_name, e);
                ObservedRecord {
                    resolver: resolver_name.to_string(),
                    values: vec![],
                    match_desired: false,
                }
            }
        }
    }

    pub fn get_consecutive_failures(&self) -> u32 {
        self.consecutive_failures
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_evidence_hash() {
        let evidence = CycleEvidence {
            cycle_id: "test-123".to_string(),
            ts_start: "2026-02-01T12:00:00Z".to_string(),
            ts_end: "2026-02-01T12:00:05Z".to_string(),
            desired: DesiredRecord {
                domain: "gaiaftcl.com".to_string(),
                record_type: "A".to_string(),
                name: "@".to_string(),
                value: "77.42.85.60".to_string(),
                ttl: 600,
            },
            observed: vec![],
            provider: ProviderAction {
                kind: "godaddy".to_string(),
                action: "none".to_string(),
                http_status: None,
                request_id: None,
                error_message: None,
            },
            status: ReconcileStatus::Valid,
            consecutive_failures: 0,
            reason_codes: vec![],
            self_hash_sha256: String::new(),
        };

        let hash = evidence.compute_hash();
        assert!(hash.starts_with("sha256:"));
        assert_eq!(hash.len(), 71); // "sha256:" + 64 hex chars
    }
}
