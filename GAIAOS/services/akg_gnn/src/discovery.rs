use anyhow::Result;
use crate::types::{ServiceDescriptor, Capability};

pub struct ServiceDiscovery {
    nats: async_nats::Client,
}

impl ServiceDiscovery {
    pub fn new(nats: async_nats::Client) -> Self {
        Self { nats }
    }
    
    pub async fn discover_all_services(&self) -> Result<Vec<ServiceDescriptor>> {
        // Planned: implement actual NATS service discovery
        // Query gaiaos.registry.list
        Ok(vec![])
    }
    
    pub async fn query_capabilities(&self, _service_id: &str) -> Result<Vec<Capability>> {
        // Planned: implement capability query via NATS
        Ok(vec![])
    }
}
