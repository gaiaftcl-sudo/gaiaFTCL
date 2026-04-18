use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntrospectionEndpoint {
    pub name: String,
    pub kind: String,            // "http" | "nats"
    pub path: Option<String>,    // if http
    pub subject: Option<String>, // if nats
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceDescriptor {
    pub name: String,
    pub version: String,
    pub container_id: String,
    pub introspection_endpoints: Vec<IntrospectionEndpoint>,
}

/// Fired by services to the central bus so AKG GNN can build the service graph.
pub const SERVICE_ANNOUNCE_SUBJECT: &str = "gaiaos.services.announce";

/// Per-service introspection request subject pattern:
/// gaiaos.introspect.service.<service_name>.request
pub fn introspection_request_subject(service_name: &str) -> String {
    format!("gaiaos.introspect.service.{service_name}.request")
}

/// Reply subject is set by requester, but we expect:
/// gaiaos.introspect.service.<service_name>.reply.<uuid>
pub fn introspection_reply_subject(service_name: &str) -> String {
    format!(
        "gaiaos.introspect.service.{service_name}.reply.{}",
        Uuid::new_v4()
    )
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceIntrospectionReply {
    pub service: String,
    pub functions: Vec<FunctionDescriptor>,
    pub call_graph_edges: Vec<CallGraphEdge>,
    pub state_keys: Vec<String>,
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionDescriptor {
    pub name: String,
    pub inputs: Vec<String>,
    pub outputs: Vec<String>,
    pub kind: String, // "http" | "nats"
    pub path: Option<String>,
    pub subject: Option<String>,
    pub side_effects: Vec<String>, // e.g., ["READ_DB", "WRITE_DB"]
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallGraphEdge {
    pub caller: String,
    pub callee: String,
    pub edge_type: String, // "CALLS"
}

/// Helper to create announcement loop task
pub async fn announce_service_loop(
    nats: async_nats::Client,
    service_name: String,
    version: String,
    container_id: String,
    endpoints: Vec<IntrospectionEndpoint>,
) {
    use tokio::time::{sleep, Duration};

    let desc = ServiceDescriptor {
        name: service_name.clone(),
        version,
        container_id,
        introspection_endpoints: endpoints,
    };

    loop {
        match serde_json::to_vec(&desc) {
            Ok(payload) => {
                if let Err(e) = nats.publish(SERVICE_ANNOUNCE_SUBJECT, payload.into()).await {
                    tracing::warn!("Failed to announce service {}: {:?}", service_name, e);
                }
            }
            Err(e) => {
                tracing::error!("Failed to serialize ServiceDescriptor: {:?}", e);
            }
        }
        sleep(Duration::from_secs(10)).await; // periodic announcement
    }
}

/// Helper to run introspection handler
pub async fn run_introspection_handler<F>(
    nats: async_nats::Client,
    service_name: String,
    introspect_fn: F,
) -> anyhow::Result<()>
where
    F: Fn() -> ServiceIntrospectionReply + Send + 'static,
{
    use futures::StreamExt;

    let subject = introspection_request_subject(&service_name);
    let mut sub = nats.subscribe(subject).await?;

    while let Some(msg) = sub.next().await {
        let reply_to = match &msg.reply {
            Some(r) => r.clone(),
            None => {
                tracing::warn!("Introspection request without reply subject");
                continue;
            }
        };

        let reply = introspect_fn();

        match serde_json::to_vec(&reply) {
            Ok(payload) => {
                if let Err(e) = nats.publish(reply_to, payload.into()).await {
                    tracing::error!("Failed to send introspection reply: {:?}", e);
                }
            }
            Err(e) => {
                tracing::error!("Failed to serialize introspection reply: {:?}", e);
            }
        }
    }

    Ok(())
}
