/*!
 * Discovery Listener - Subscribe to service announcements on NATS
 *
 * Listens to `gaiaos.services.announce` and builds the service registry
 * for consciousness layer completeness checking.
 */

use futures::StreamExt;
use gaiaos_introspection::{ServiceDescriptor, SERVICE_ANNOUNCE_SUBJECT};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};

/// Service registry shared across AKG GNN
#[derive(Clone)]
pub struct ServiceRegistry {
    services: Arc<RwLock<HashMap<String, ServiceDescriptor>>>,
}

impl ServiceRegistry {
    pub fn new() -> Self {
        Self {
            services: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Register or update a service
    pub async fn register(&self, descriptor: ServiceDescriptor) {
        let mut services = self.services.write().await;
        let name = descriptor.name.clone();
        services.insert(name.clone(), descriptor);
        info!("Registered service: {}", name);
    }

    /// Get all registered services
    pub async fn list_services(&self) -> Vec<ServiceDescriptor> {
        let services = self.services.read().await;
        services.values().cloned().collect()
    }

    /// Get service count
    pub async fn count(&self) -> usize {
        let services = self.services.read().await;
        services.len()
    }

    /// Check if a service is registered
    pub async fn has_service(&self, name: &str) -> bool {
        let services = self.services.read().await;
        services.contains_key(name)
    }
}

/// Start discovery listener task
pub async fn start_discovery_listener(
    nats: async_nats::Client,
    registry: ServiceRegistry,
) -> anyhow::Result<()> {
    info!(
        "Starting service discovery listener on {}",
        SERVICE_ANNOUNCE_SUBJECT
    );

    let mut sub = nats.subscribe(SERVICE_ANNOUNCE_SUBJECT).await?;

    while let Some(msg) = sub.next().await {
        match serde_json::from_slice::<ServiceDescriptor>(&msg.payload) {
            Ok(descriptor) => {
                registry.register(descriptor).await;
            }
            Err(e) => {
                warn!("Failed to parse service announcement: {:?}", e);
            }
        }
    }

    error!("Discovery listener stopped unexpectedly");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_service_registry() {
        let registry = ServiceRegistry::new();

        let descriptor = ServiceDescriptor {
            name: "test-service".into(),
            version: "1.0.0".into(),
            container_id: "test-container".into(),
            introspection_endpoints: vec![],
        };

        registry.register(descriptor.clone()).await;

        assert_eq!(registry.count().await, 1);
        assert!(registry.has_service("test-service").await);

        let services = registry.list_services().await;
        assert_eq!(services.len(), 1);
        assert_eq!(services[0].name, "test-service");
    }
}
