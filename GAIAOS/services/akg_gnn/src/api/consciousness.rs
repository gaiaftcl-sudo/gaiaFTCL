/*!
 * Consciousness API - Expose service discovery and self-knowledge
 */

use actix_web::{get, web, HttpResponse, Responder};
use serde::Serialize;
use std::sync::Arc;

use crate::discovery_listener::ServiceRegistry;

#[derive(Serialize)]
pub struct ServiceDiscoveryResponse {
    pub services: Vec<gaiaos_introspection::ServiceDescriptor>,
    pub count: usize,
}

#[derive(Serialize)]
pub struct ServiceCheckResponse {
    pub service_name: String,
    pub registered: bool,
}

/// GET /consciousness/services - List all discovered services
#[get("/consciousness/services")]
pub async fn list_services(registry: web::Data<Arc<ServiceRegistry>>) -> impl Responder {
    let services = registry.list_services().await;
    let count = services.len();

    HttpResponse::Ok().json(ServiceDiscoveryResponse { services, count })
}

/// GET /consciousness/count - Get service count
#[get("/consciousness/count")]
pub async fn service_count(registry: web::Data<Arc<ServiceRegistry>>) -> impl Responder {
    let count = registry.count().await;

    HttpResponse::Ok().json(serde_json::json!({
        "service_count": count
    }))
}

/// GET /consciousness/check/{service_name} - Check if service is registered
#[get("/consciousness/check/{service_name}")]
pub async fn check_service(
    registry: web::Data<Arc<ServiceRegistry>>,
    service_name: web::Path<String>,
) -> impl Responder {
    let registered = registry.has_service(&service_name).await;

    HttpResponse::Ok().json(ServiceCheckResponse {
        service_name: service_name.into_inner(),
        registered,
    })
}
