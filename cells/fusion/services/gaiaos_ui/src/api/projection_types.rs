//! Projection Types Registry API
//!
//! GET /api/projection-types - Returns the list of projection types

use axum::{response::IntoResponse, Json};
use serde::Serialize;

/// Projection type metadata matching frontend `ProjectionTypeMeta` interface
#[derive(Debug, Serialize)]
pub struct ProjectionTypeMeta {
    pub kind: String,
    pub label: String,
    #[serde(rename = "schemaRef", skip_serializing_if = "Option::is_none")]
    pub schema_ref: Option<String>,
    #[serde(rename = "defaultComponent", skip_serializing_if = "Option::is_none")]
    pub default_component: Option<String>,
}

/// GET /api/projection-types
/// Returns the list of projection types
pub async fn list() -> impl IntoResponse {
    let types = vec![
        ProjectionTypeMeta {
            kind: "text".to_string(),
            label: "Text Response".to_string(),
            schema_ref: Some("#/TextProjectionEvent".to_string()),
            default_component: Some("TextBubble".to_string()),
        },
        ProjectionTypeMeta {
            kind: "audio".to_string(),
            label: "Audio Response".to_string(),
            schema_ref: Some("#/AudioProjectionEvent".to_string()),
            default_component: Some("AudioPlayer".to_string()),
        },
        ProjectionTypeMeta {
            kind: "image".to_string(),
            label: "Image".to_string(),
            schema_ref: Some("#/ImageProjectionEvent".to_string()),
            default_component: Some("ImageViewer".to_string()),
        },
        ProjectionTypeMeta {
            kind: "video".to_string(),
            label: "Video".to_string(),
            schema_ref: Some("#/VideoProjectionEvent".to_string()),
            default_component: Some("VideoPlayer".to_string()),
        },
        ProjectionTypeMeta {
            kind: "akg_graph".to_string(),
            label: "Knowledge Graph".to_string(),
            schema_ref: Some("#/AKGGraphProjectionEvent".to_string()),
            default_component: Some("AKGGraphView".to_string()),
        },
        ProjectionTypeMeta {
            kind: "exam_terminal".to_string(),
            label: "Exam Terminal".to_string(),
            schema_ref: Some("#/ExamTerminalProjectionEvent".to_string()),
            default_component: Some("ExamTerminalView".to_string()),
        },
        ProjectionTypeMeta {
            kind: "system_status".to_string(),
            label: "System Status".to_string(),
            schema_ref: Some("#/SystemStatusProjectionEvent".to_string()),
            default_component: Some("SystemStatusCard".to_string()),
        },
        ProjectionTypeMeta {
            kind: "debug".to_string(),
            label: "Debug Info".to_string(),
            schema_ref: None,
            default_component: Some("DefaultProjectionRenderer".to_string()),
        },
    ];
    
    Json(types)
}

