//! Message types for the Spatial Gateway WebSocket protocol
//! 
//! All messages use a single envelope schema so agents can stay generic.
//! The protocol supports:
//! - hello/hello_ack for handshake
//! - pose_update for streaming location data
//! - sensor_update for other sensor data
//! - query/query_result for truth field queries
//! - subscribe/unsubscribe for streaming subscriptions
//! - error for error responses

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use super::cell::QosParams;
use super::vqbit::Vqbit8D;

/// Message types in the protocol
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MessageType {
    /// Initial handshake from cell
    Hello,
    /// Handshake acknowledgment from gateway
    HelloAck,
    /// Pose/location update from cell
    PoseUpdate,
    /// Generic sensor update from cell
    SensorUpdate,
    /// Query for truth field data
    Query,
    /// Response to a query
    QueryResult,
    /// Subscribe to streaming updates
    Subscribe,
    /// Unsubscribe from streaming
    Unsubscribe,
    /// Subscription update pushed to client
    SubscriptionUpdate,
    /// Ingest acknowledgment
    IngestAck,
    /// Error response
    Error,
}

/// Generic message envelope
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Envelope<T> {
    /// Message type discriminator
    #[serde(rename = "type")]
    pub msg_type: MessageType,
    /// Session identifier (assigned by gateway)
    pub session_id: Option<Uuid>,
    /// Cell identifier
    pub cell_id: Option<Uuid>,
    /// Sequence number for ordering
    pub seq: Option<u64>,
    /// ISO 8601 timestamp
    pub ts: String,
    /// Type-specific payload
    pub payload: T,
}

/// Authentication info for cell handshake
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AuthInfo {
    /// JWT token for identity verification
    pub jwt: Option<String>,
    /// Cryptographic signature over nonce
    pub signature: Option<String>,
    /// Public key for verification
    pub public_key: Option<String>,
}

/// Payload for hello message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelloPayload {
    /// Domain affiliation
    pub domain: String,
    /// Advertised capabilities
    pub capabilities: Vec<String>,
    /// Authentication info
    #[serde(default)]
    pub auth: AuthInfo,
}

/// Payload for hello_ack message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelloAckPayload {
    /// Status (ok or error)
    pub status: String,
    /// Negotiated QoS parameters
    pub qos: QosParams,
    /// Error message if status != ok
    pub error: Option<String>,
}

/// GeoPose position (EPSG:4979 - WGS84 with ellipsoidal height)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Position {
    /// Latitude in degrees
    pub lat: f64,
    /// Longitude in degrees
    pub lon: f64,
    /// Altitude in meters (ellipsoidal height)
    pub alt: f64,
}

/// Quaternion orientation (OpenXR compatible)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Orientation {
    /// W component (scalar)
    pub w: f32,
    /// X component
    pub x: f32,
    /// Y component
    pub y: f32,
    /// Z component
    pub z: f32,
}

impl Default for Orientation {
    fn default() -> Self {
        Self { w: 1.0, x: 0.0, y: 0.0, z: 0.0 }
    }
}

/// Payload for pose_update message (GeoPose/OpenXR compatible)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeoPosePayload {
    /// Coordinate reference frame (e.g., "EPSG:4979")
    #[serde(default = "default_frame")]
    pub frame: String,
    /// Position in the frame
    pub position: Position,
    /// Orientation as quaternion
    #[serde(default)]
    pub orientation: Orientation,
    /// Position uncertainty in meters
    #[serde(default = "default_uncertainty")]
    pub uncertainty_m: f32,
    /// Source of this pose data
    #[serde(default = "default_source")]
    pub source: String,
    /// Velocity in m/s (optional)
    pub velocity: Option<[f32; 3]>,
    /// Angular velocity in rad/s (optional)
    pub angular_velocity: Option<[f32; 3]>,
    /// Optional metadata for semantic classification
    pub metadata: Option<serde_json::Value>,
    /// Timestamp of observation (unix seconds)
    pub timestamp_unix: Option<f64>,
}

fn default_frame() -> String { "EPSG:4979".to_string() }
fn default_uncertainty() -> f32 { 10.0 }
fn default_source() -> String { "UNKNOWN".to_string() }

/// Payload for sensor_update message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensorPayload {
    /// Sensor type (e.g., "radar", "lidar", "camera")
    pub sensor_type: String,
    /// Sensor-specific data as JSON
    pub data: serde_json::Value,
    /// Confidence/quality score 0-1
    pub confidence: f32,
}

/// Payload for query message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryPayload {
    /// Optional domain filter
    pub domain: Option<String>,
    /// Bounding box minimum longitude
    pub lon_min: f64,
    /// Bounding box maximum longitude
    pub lon_max: f64,
    /// Bounding box minimum latitude
    pub lat_min: f64,
    /// Bounding box maximum latitude
    pub lat_max: f64,
    /// Optional time window start (unix seconds)
    pub t_min: Option<f64>,
    /// Optional time window end (unix seconds)
    pub t_max: Option<f64>,
    /// Maximum results to return
    pub limit: Option<u32>,
}

/// Single sample in query results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryResultSample {
    /// Cell that produced this sample
    pub cell_id: Uuid,
    /// Domain of the cell
    pub domain: String,
    /// 8D vQbit representation
    pub vqbit: Vqbit8D,
    /// Timestamp (unix seconds)
    pub ts_unix: f64,
    /// FoT validation status
    pub fot_validated: bool,
    /// Virtue weight (0-1)
    pub virtue_weight: f32,
}

/// Payload for query_result message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryResultPayload {
    /// Matching samples
    pub samples: Vec<QueryResultSample>,
    /// Total count (may be more than returned if limited)
    pub total_count: usize,
    /// Whether results were truncated
    pub truncated: bool,
}

/// Payload for subscribe message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubscribePayload {
    /// Subscription ID (client-provided)
    pub subscription_id: String,
    /// Query defining the subscription region
    pub query: QueryPayload,
    /// Update frequency in Hz
    pub update_hz: Option<u32>,
}

/// Payload for subscription_update message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubscriptionUpdatePayload {
    /// Subscription ID this update belongs to
    pub subscription_id: String,
    /// Updated samples
    pub samples: Vec<QueryResultSample>,
}

/// Payload for error message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorPayload {
    /// Error code
    pub code: String,
    /// Human-readable message
    pub message: String,
    /// Additional details
    pub details: Option<serde_json::Value>,
}

/// Payload for ingest_ack message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestAckPayload {
    /// ID of the ingested vQbit
    pub vqbit_id: Uuid,
    /// Coherence score from fusion
    pub coherence_score: f32,
    /// Number of conflicts detected
    pub conflicts_count: usize,
}
