//! Service announcement and introspection handler for AKG GNN itself

use gaiaos_introspection::{
    announce_service_loop, run_introspection_handler, FunctionDescriptor, IntrospectionEndpoint,
    ServiceIntrospectionReply,
};
use tokio::task::JoinHandle;

/// Start AKG GNN's own service announcement loop
pub fn start_announcement(
    nats: async_nats::Client,
    service_name: String,
    version: String,
    container_id: String,
) -> JoinHandle<()> {
    let endpoints = vec![
        IntrospectionEndpoint {
            name: "introspect".into(),
            kind: "nats".into(),
            path: None,
            subject: Some(format!("gaiaos.introspect.service.{service_name}.request")),
        },
        IntrospectionEndpoint {
            name: "health".into(),
            kind: "http".into(),
            path: Some("/health".into()),
            subject: None,
        },
    ];

    tokio::spawn(announce_service_loop(
        nats,
        service_name,
        version,
        container_id,
        endpoints,
    ))
}

/// Start AKG GNN's introspection handler
pub fn start_introspection_handler(
    nats: async_nats::Client,
    service_name: String,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let introspect_fn = move || {
            ServiceIntrospectionReply {
                service: service_name.clone(),
                functions: vec![
                    FunctionDescriptor {
                        name: "akg_gnn::introspect_services".into(),
                        inputs: vec![],
                        outputs: vec!["Vec<ServiceDescriptor>".into()],
                        kind: "http".into(),
                        path: Some("/introspect/services".into()),
                        subject: None,
                        side_effects: vec!["READ_GRAPH".into()],
                    },
                    FunctionDescriptor {
                        name: "akg_gnn::introspect_functions".into(),
                        inputs: vec![],
                        outputs: vec!["Vec<FunctionDescriptor>".into()],
                        kind: "http".into(),
                        path: Some("/introspect/functions".into()),
                        subject: None,
                        side_effects: vec!["READ_GRAPH".into()],
                    },
                    FunctionDescriptor {
                        name: "akg_gnn::check_completeness".into(),
                        inputs: vec![],
                        outputs: vec!["CompletenessReport".into()],
                        kind: "http".into(),
                        path: Some("/introspect/completeness".into()),
                        subject: None,
                        side_effects: vec!["READ_GRAPH".into()],
                    },
                    FunctionDescriptor {
                        name: "akg_gnn::assess_consciousness".into(),
                        inputs: vec![],
                        outputs: vec!["ConsciousnessAssessment".into()],
                        kind: "http".into(),
                        path: Some("/consciousness/assess".into()),
                        subject: None,
                        side_effects: vec!["READ_GRAPH".into(), "COMPUTE_METRICS".into()],
                    },
                ],
                call_graph_edges: vec![
                    // AKG GNN calls Franklin Guardian
                    gaiaos_introspection::CallGraphEdge {
                        caller: "akg_gnn".into(),
                        callee: "franklin-guardian".into(),
                        edge_type: "CALLS".into(),
                    },
                ],
                state_keys: vec!["knowledge_graph".into(), "service_registry".into()],
                timestamp: chrono::Utc::now().to_rfc3339(),
            }
        };

        if let Err(e) = run_introspection_handler(nats, service_name, introspect_fn).await {
            tracing::error!("AKG GNN introspection handler failed: {:?}", e);
        }
    })
}
