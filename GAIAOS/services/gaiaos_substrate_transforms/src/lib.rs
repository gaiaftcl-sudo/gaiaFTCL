/// GaiaOS Substrate Transforms - Language Game Mappings
/// 
/// Purpose: Transform substrate entities to UI world "skins"
/// Philosophy: Wittgensteinian language games - same concept, different meanings

use serde::{Deserialize, Serialize};

// ============================================================================
// SUBSTRATE CANONICAL TYPES (Ground Truth)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstrateEntity {
    pub id: String,
    pub entity_type: EntityType,
    pub position: Position8D,
    pub velocity: Velocity8D,
    pub mass: f64,
    pub virtue_weights: VirtueWeights,
    pub decision_state: Option<DecisionState>,
    pub consciousness_link: ConsciousnessLink,
    pub timestamp: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EntityType {
    Aircraft,
    Satellite,
    Agent,
    Resource,
    Decision,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Position8D {
    pub dim1: (f64, f64, f64),  // Physical space (x, y, z) or (lat, lon, alt)
    pub dim2: (f64, f64, f64),  // Network topology
    pub dim3: (f64, f64, f64),  // Temporal flow
    pub dim4: (f64, f64, f64),  // Decision space
    pub dim5: (f64, f64, f64),  // Energy/resource
    pub dim6: (f64, f64, f64),  // Information density
    pub dim7: (f64, f64, f64),  // Virtue alignment
    pub dim8: (f64, f64, f64),  // Meta-awareness
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Velocity8D {
    pub dim1: (f64, f64, f64),
    pub dim2: (f64, f64, f64),
    pub dim3: (f64, f64, f64),
    pub dim4: (f64, f64, f64),
    pub dim5: (f64, f64, f64),
    pub dim6: (f64, f64, f64),
    pub dim7: (f64, f64, f64),
    pub dim8: (f64, f64, f64),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueWeights {
    pub truth: f64,
    pub justice: f64,
    pub mercy: f64,
    pub wisdom: f64,
    pub courage: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecisionState {
    pub complexity: f64,
    pub uncertainty: f64,
    pub guardian_approved: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessLink {
    pub awareness_level: f64,
    pub attention_focus: f64,
    pub reasoning_depth: u32,
    pub certainty: f64,
}

// ============================================================================
// LANGUAGE GAME 1: ATC FAA (AVIATION)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Aircraft {
    pub callsign: String,
    pub aircraft_type: String,
    
    // Physical Position (Dimension 1 only)
    pub lat: f64,           // Degrees
    pub lon: f64,           // Degrees
    pub alt: f64,           // Feet MSL
    
    // Aviation Velocity
    pub ground_speed: f64,   // Knots
    pub heading: f64,        // Degrees true
    pub vertical_speed: f64, // FPM
    
    // Aviation Status
    pub status: String,
    pub flight_phase: String,
    
    // Guardian Oversight (Aviation Context)
    pub separation_compliant: bool,
    pub virtue_status: String,
}

/// Transform substrate entity to ATC aircraft
pub fn substrate_to_aircraft(entity: &SubstrateEntity) -> Aircraft {
    let (x, y, z) = entity.position.dim1;
    let (vx, vy, vz) = entity.velocity.dim1;
    
    // Convert velocity to aviation terms
    let ground_speed = (vx * vx + vy * vy).sqrt() * 1.94384; // m/s to knots
    let heading = vy.atan2(vx).to_degrees();
    let vertical_speed = vz * 196.85; // m/s to feet per minute
    
    // Virtue status
    let virtue_status = if entity.virtue_weights.truth > 0.5 
        && entity.virtue_weights.mercy > 0.5 {
        "compliant".to_string()
    } else {
        "warning".to_string()
    };
    
    Aircraft {
        callsign: if entity.id.len() >= 6 {
            format!("AC{}", &entity.id[..6])
        } else {
            format!("AC{}", entity.id)
        },
        aircraft_type: "B737".to_string(),
        lat: x,
        lon: y,
        alt: z * 3.28084, // meters to feet
        ground_speed,
        heading: if heading < 0.0 { heading + 360.0 } else { heading },
        vertical_speed,
        status: "active".to_string(),
        flight_phase: "cruise".to_string(),
        separation_compliant: entity.virtue_weights.justice > 0.5,
        virtue_status,
    }
}

// ============================================================================
// LANGUAGE GAME 2: ASTRO WORLDS (ORBITAL)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrbitalEntity {
    pub substrate_id: String,
    pub catalog_id: String,
    pub name: String,
    
    // Orbital Position (Dimension 1 in ECI coordinates)
    pub position: (f32, f32, f32),  // Meters from Earth center
    pub velocity: (f32, f32, f32),  // m/s in ECI frame
    
    // Orbital Elements
    pub semi_major_axis: f64,
    pub eccentricity: f64,
    pub inclination: f64,
    
    // Physical Properties
    pub mass: f64,
    
    // Guardian Oversight (Orbital Context)
    pub min_separation: f64,
    pub guardian_monitored: bool,
    
    // Consciousness Properties
    pub awareness_level: f64,
}

/// Transform substrate entity to orbital satellite
pub fn substrate_to_orbital(entity: &SubstrateEntity) -> OrbitalEntity {
    let (x, y, z) = entity.position.dim1;
    let (vx, vy, vz) = entity.velocity.dim1;
    
    // Position/velocity magnitude for orbital elements
    let r = (x*x + y*y + z*z).sqrt();
    let _v = (vx*vx + vy*vy + vz*vz).sqrt();
    
    // Simplified orbital elements (for demonstration)
    let semi_major_axis = r;
    let eccentricity = 0.0; // Assume circular for now
    let inclination = (z / r).asin();
    
    OrbitalEntity {
        substrate_id: entity.id.clone(),
        catalog_id: format!("{:05}", &entity.id[..5].parse::<u32>().unwrap_or(99999)),
        name: format!("SAT-{}", &entity.id[..4]),
        position: (x as f32, y as f32, z as f32),
        velocity: (vx as f32, vy as f32, vz as f32),
        semi_major_axis,
        eccentricity,
        inclination,
        mass: entity.mass,
        min_separation: 1000.0, // 1 km minimum
        guardian_monitored: entity.virtue_weights.justice > 0.5,
        awareness_level: entity.consciousness_link.awareness_level,
    }
}

// ============================================================================
// LANGUAGE GAME 3: SMALL WORLD DIMENSION 1 (PHYSICAL)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysicalEntity {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub vx: f64,
    pub vy: f64,
    pub vz: f64,
}

pub fn substrate_to_physical(entity: &SubstrateEntity) -> PhysicalEntity {
    let (x, y, z) = entity.position.dim1;
    let (vx, vy, vz) = entity.velocity.dim1;
    
    PhysicalEntity {
        id: entity.id.clone(),
        x, y, z,
        vx, vy, vz,
    }
}

// ============================================================================
// LANGUAGE GAME 4: SMALL WORLD DIMENSION 2 (NETWORK)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkNode {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub bandwidth: f64,
    pub latency: f64,
}

pub fn substrate_to_network(entity: &SubstrateEntity) -> NetworkNode {
    let (x, y, _) = entity.position.dim2;
    let (vx, vy, _) = entity.velocity.dim2;
    let bandwidth = (vx*vx + vy*vy).sqrt();
    
    NetworkNode {
        id: entity.id.clone(),
        x, y,
        bandwidth,
        latency: 1.0 / (bandwidth + 0.1), // Inverse relationship
    }
}

// ============================================================================
// LANGUAGE GAME 5: SMALL WORLD DIMENSION 4 (DECISION)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecisionEntity {
    pub id: String,
    pub complexity_x: f64,
    pub uncertainty_y: f64,
    pub virtue_weights: VirtueWeights,
    pub guardian_approved: bool,
}

pub fn substrate_to_decision(entity: &SubstrateEntity) -> DecisionEntity {
    let (x, y, _) = entity.position.dim4;
    
    DecisionEntity {
        id: entity.id.clone(),
        complexity_x: x,
        uncertainty_y: y,
        virtue_weights: entity.virtue_weights.clone(),
        guardian_approved: entity.decision_state
            .as_ref()
            .map(|d| d.guardian_approved)
            .unwrap_or(false),
    }
}

// ============================================================================
// LANGUAGE GAME 6: SMALL WORLD DIMENSION 7 (VIRTUE)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueEntity {
    pub id: String,
    pub truth_axis: f64,
    pub justice_axis: f64,
    pub virtues: VirtueWeights,
    pub constitutional_compliance: bool,
}

pub fn substrate_to_virtue(entity: &SubstrateEntity) -> VirtueEntity {
    let constitutional_compliance = 
        entity.virtue_weights.truth >= 0.5
        && entity.virtue_weights.justice >= 0.5
        && entity.virtue_weights.mercy >= 0.5;
    
    VirtueEntity {
        id: entity.id.clone(),
        truth_axis: entity.virtue_weights.truth,
        justice_axis: entity.virtue_weights.justice,
        virtues: entity.virtue_weights.clone(),
        constitutional_compliance,
    }
}

// ============================================================================
// LANGUAGE GAME 7: SMALL WORLD DIMENSION 8 (CONSCIOUSNESS)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessEntity {
    pub id: String,
    pub awareness_level: f64,
    pub introspection_depth: f64,
    pub reasoning_depth: u32,
    pub agi_focus: String,
}

pub fn substrate_to_consciousness(entity: &SubstrateEntity) -> ConsciousnessEntity {
    let (_, introspection, _) = entity.position.dim8;
    
    let agi_focus = if entity.consciousness_link.attention_focus > 0.7 {
        "high".to_string()
    } else if entity.consciousness_link.attention_focus > 0.3 {
        "medium".to_string()
    } else {
        "low".to_string()
    };
    
    ConsciousnessEntity {
        id: entity.id.clone(),
        awareness_level: entity.consciousness_link.awareness_level,
        introspection_depth: introspection,
        reasoning_depth: entity.consciousness_link.reasoning_depth,
        agi_focus,
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_entity() -> SubstrateEntity {
        SubstrateEntity {
            id: "e8f3a2b1-1234-5678-90ab-cdef01234567".to_string(),
            entity_type: EntityType::Aircraft,
            position: Position8D {
                dim1: (41.5, -71.3, 10668.0),  // Lat/lon/alt meters
                dim2: (0.2, 0.8, 0.1),
                dim3: (0.0, 0.0, 0.0),
                dim4: (0.7, 0.3, 0.0),
                dim5: (0.5, 0.5, 0.0),
                dim6: (0.6, 0.4, 0.0),
                dim7: (0.85, 0.78, 0.0),
                dim8: (0.87, 0.65, 0.0),
            },
            velocity: Velocity8D {
                dim1: (100.0, 50.0, 5.0),
                dim2: (0.1, 0.2, 0.0),
                dim3: (0.0, 0.0, 0.0),
                dim4: (0.0, 0.0, 0.0),
                dim5: (0.0, 0.0, 0.0),
                dim6: (0.0, 0.0, 0.0),
                dim7: (0.0, 0.0, 0.0),
                dim8: (0.0, 0.0, 0.0),
            },
            mass: 70000.0,
            virtue_weights: VirtueWeights {
                truth: 0.85,
                justice: 0.78,
                mercy: 0.92,
                wisdom: 0.88,
                courage: 0.75,
            },
            decision_state: Some(DecisionState {
                complexity: 0.7,
                uncertainty: 0.3,
                guardian_approved: true,
            }),
            consciousness_link: ConsciousnessLink {
                awareness_level: 0.87,
                attention_focus: 0.65,
                reasoning_depth: 3,
                certainty: 0.92,
            },
            timestamp: 1702400000,
        }
    }

    #[test]
    fn test_aircraft_transformation() {
        let entity = create_test_entity();
        let aircraft = substrate_to_aircraft(&entity);
        
        assert_eq!(aircraft.lat, 41.5);
        assert_eq!(aircraft.lon, -71.3);
        assert!(aircraft.alt > 35000.0); // ~35,000 feet
        assert!(aircraft.ground_speed > 0.0);
        assert_eq!(aircraft.virtue_status, "compliant");
    }

    #[test]
    fn test_orbital_transformation() {
        let entity = create_test_entity();
        let orbital = substrate_to_orbital(&entity);
        
        assert_eq!(orbital.substrate_id, entity.id);
        assert!(orbital.semi_major_axis > 0.0);
        assert_eq!(orbital.awareness_level, 0.87);
    }

    #[test]
    fn test_virtue_transformation() {
        let entity = create_test_entity();
        let virtue = substrate_to_virtue(&entity);
        
        assert_eq!(virtue.truth_axis, 0.85);
        assert_eq!(virtue.justice_axis, 0.78);
        assert!(virtue.constitutional_compliance); // All virtues > 0.5
    }

    #[test]
    fn test_consciousness_transformation() {
        let entity = create_test_entity();
        let consciousness = substrate_to_consciousness(&entity);
        
        assert_eq!(consciousness.awareness_level, 0.87);
        assert_eq!(consciousness.reasoning_depth, 3);
        assert_eq!(consciousness.agi_focus, "medium");
    }
}
