//! Cell identity and domain definitions
//! 
//! Each cell represents a sovereign entity in the GaiaOS mesh:
//! - Drones, phones, cars, towers, ATC radars, etc.
//! - Each has a unique identity and domain affiliation

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Domain types for cells - determines truth surface routing
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CellDomain {
    /// Air Traffic Control
    Atc,
    /// Autonomous Vehicles
    Av,
    /// Maritime navigation
    Maritime,
    /// Weather systems
    Weather,
    /// AR/Gaming (Niantic-class apps)
    Game,
    /// General purpose
    General,
    /// Medical systems
    Medical,
    /// Infrastructure monitoring
    Infrastructure,
    /// Unknown/unregistered
    Unknown,
}

impl Default for CellDomain {
    fn default() -> Self {
        Self::Unknown
    }
}

impl std::fmt::Display for CellDomain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CellDomain::Atc => write!(f, "ATC"),
            CellDomain::Av => write!(f, "AV"),
            CellDomain::Maritime => write!(f, "MARITIME"),
            CellDomain::Weather => write!(f, "WEATHER"),
            CellDomain::Game => write!(f, "GAME"),
            CellDomain::General => write!(f, "GENERAL"),
            CellDomain::Medical => write!(f, "MEDICAL"),
            CellDomain::Infrastructure => write!(f, "INFRASTRUCTURE"),
            CellDomain::Unknown => write!(f, "UNKNOWN"),
        }
    }
}

/// Capabilities a cell can advertise
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CellCapability {
    /// Can provide pose/location updates
    Pose,
    /// Has IMU sensors
    Imu,
    /// Has radar systems
    Radar,
    /// Has lidar sensors
    Lidar,
    /// Has camera/vision
    Camera,
    /// Has GPS
    Gps,
    /// Has RTK GPS (high precision)
    Rtk,
    /// Can receive commands
    Actuator,
    /// Can run local inference
    Inference,
    /// Custom capability
    Custom(String),
}

/// QoS parameters for a cell session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QosParams {
    /// Maximum update frequency in Hz
    pub max_hz: u32,
    /// Maximum payload size in bytes
    pub max_payload_bytes: u32,
    /// Priority level (higher = more important)
    pub priority: u8,
}

impl Default for QosParams {
    fn default() -> Self {
        Self {
            max_hz: 120,
            max_payload_bytes: 16384,
            priority: 5,
        }
    }
}

/// Registered cell session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CellSession {
    /// Unique cell identifier
    pub cell_id: Uuid,
    /// Session identifier (changes on reconnect)
    pub session_id: Uuid,
    /// Cell's domain affiliation
    pub domain: CellDomain,
    /// Advertised capabilities
    pub capabilities: Vec<CellCapability>,
    /// Negotiated QoS parameters
    pub qos: QosParams,
    /// Session start time (unix seconds)
    pub connected_at: f64,
    /// Last activity time (unix seconds)
    pub last_activity: f64,
}
