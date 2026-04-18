//! Capability Gate checking
//!
//! Reads CapabilityGate status from the validation instances TTL
//! and determines what autonomy level is allowed for each domain.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::fs;
use anyhow::Result;
use log::info;

/// Autonomy level for a capability
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GateStatus {
    /// Full autonomy - Gaia can act freely
    Full,
    /// Restricted - Gaia can act within bounds
    Restricted,
    /// Human must approve each action
    HumanRequired,
    /// Capability is disabled
    Disabled,
}

impl GateStatus {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "full" => GateStatus::Full,
            "restricted" => GateStatus::Restricted,
            "human_required" => GateStatus::HumanRequired,
            _ => GateStatus::Disabled,
        }
    }
    
    pub fn allows_autonomous_action(&self) -> bool {
        matches!(self, GateStatus::Full | GateStatus::Restricted)
    }
    
    pub fn icon(&self) -> &'static str {
        match self {
            GateStatus::Full => "🟢",
            GateStatus::Restricted => "🟡",
            GateStatus::HumanRequired => "🟠",
            GateStatus::Disabled => "🔴",
        }
    }
}

/// Information about a capability gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityGate {
    pub capability: String,
    pub family: String,
    pub status: GateStatus,
    pub virtue_threshold: f32,
    pub current_virtue: Option<f32>,
    pub has_iq: bool,
    pub has_oq: bool,
    pub has_pq: bool,
}

impl CapabilityGate {
    pub fn is_validated(&self) -> bool {
        self.has_iq && self.has_oq && self.has_pq
    }
    
    pub fn meets_virtue_threshold(&self) -> bool {
        self.current_virtue.map(|v| v >= self.virtue_threshold).unwrap_or(false)
    }
}

/// Gate checker that reads TTL and provides gate status
#[derive(Clone)]
#[derive(Default)]
pub struct GateChecker {
    gates: HashMap<String, CapabilityGate>,
}

impl GateChecker {
    /// Create a new gate checker from validation TTL
    pub fn from_ttl(ttl_path: &Path) -> Result<Self> {
        let content = fs::read_to_string(ttl_path)?;
        let gates = Self::parse_gates(&content);
        
        info!("Loaded {} capability gates from TTL", gates.len());
        
        Ok(GateChecker { gates })
    }
    
    /// Parse capability gates from TTL content
    fn parse_gates(content: &str) -> HashMap<String, CapabilityGate> {
        let mut gates = HashMap::new();
        
        // Simple line-by-line parsing (in production, use a proper RDF parser)
        // Split into blocks starting with gaia:CapabilityGate_
        let blocks: Vec<&str> = content.split("gaia:CapabilityGate_").collect();
        
        for block in blocks.iter().skip(1) { // Skip first empty block
            // Extract capability name (first word)
            let cap_name: String = block.chars()
                .take_while(|c| c.is_alphanumeric())
                .collect();
            
            if cap_name.is_empty() { continue; }
            
            // Get the properties block (until next major declaration)
            let props_end = block.find("\ngaia:").unwrap_or(block.len());
            let properties = &block[..props_end];
            
            // Extract autonomy level
            let autonomy = Self::extract_quoted_value(properties, "gaia:autonomyLevel")
                .unwrap_or("disabled".to_string());
            
            // Extract virtue threshold
            let threshold = Self::extract_quoted_value(properties, "gaia:virtueThreshold")
                .and_then(|s| s.parse::<f32>().ok())
                .unwrap_or(0.90);
            
            // Extract current virtue
            let virtue = Self::extract_quoted_value(properties, "gaia:currentVirtue")
                .and_then(|s| s.parse::<f32>().ok());
            
            // Check for validation backing
            let has_iq = properties.contains("gaia:gateBackedByIQ");
            let has_oq = properties.contains("gaia:gateBackedByOQ");
            let has_pq = properties.contains("gaia:gateBackedByPQ");
            
            // Map capability name to family
            let family = Self::capability_to_family(&cap_name);
            
            let gate = CapabilityGate {
                capability: cap_name.clone(),
                family: family.to_string(),
                status: GateStatus::from_str(&autonomy),
                virtue_threshold: threshold,
                current_virtue: virtue,
                has_iq,
                has_oq,
                has_pq,
            };
            
            gates.insert(family.to_string(), gate);
        }
        
        gates
    }
    
    /// Extract a quoted value from TTL properties
    fn extract_quoted_value(text: &str, predicate: &str) -> Option<String> {
        let pat = format!("{predicate} \"");
        if let Some(start) = text.find(&pat) {
            let value_start = start + pat.len();
            let remaining = &text[value_start..];
            if let Some(end) = remaining.find('"') {
                return Some(remaining[..end].to_string());
            }
        }
        None
    }
    
    /// Map capability name to domain family
    fn capability_to_family(capability: &str) -> &str {
        match capability {
            "ComputerUse" => "computer_use",
            "MathReasoning" => "math",
            "CodeAuthoring" => "code",
            "GalaxyModeling" => "galaxy",
            "ChemistryReasoning" => "chemistry",
            "MedicalReasoning" => "medical",
            "ProteinModeling" => "protein",
            "VisionUnderstanding" => "vision",
            "WorldModeling" => "world_models",
            "GeneralReasoning" => "general_reasoning",
            _ => capability,
        }
    }
    
    /// Get gate status for a domain
    pub fn get_gate(&self, domain: &str) -> Option<&CapabilityGate> {
        self.gates.get(domain)
    }
    
    /// Check if a domain allows autonomous action
    pub fn allows_autonomous(&self, domain: &str) -> bool {
        self.gates.get(domain)
            .map(|g| g.status.allows_autonomous_action())
            .unwrap_or(false)
    }
    
    /// Get status for a domain
    pub fn get_status(&self, domain: &str) -> GateStatus {
        self.gates.get(domain)
            .map(|g| g.status)
            .unwrap_or(GateStatus::Disabled)
    }
    
    /// Get all gates
    pub fn all_gates(&self) -> &HashMap<String, CapabilityGate> {
        &self.gates
    }
    
    /// Print gate summary
    pub fn print_summary(&self) {
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("🔐 CAPABILITY GATES");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        let mut sorted: Vec<_> = self.gates.iter().collect();
        sorted.sort_by_key(|(_, g)| match g.status {
            GateStatus::Full => 0,
            GateStatus::Restricted => 1,
            GateStatus::HumanRequired => 2,
            GateStatus::Disabled => 3,
        });
        
        for (domain, gate) in sorted {
            let virtue_str = gate.current_virtue
                .map(|v| format!("{v:.2}"))
                .unwrap_or("-".to_string());
            
            println!("  {} {} [{:?}] virtue={}", 
                gate.status.icon(), 
                domain, 
                gate.status,
                virtue_str
            );
        }
        
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    }
}

// Add regex dependency

