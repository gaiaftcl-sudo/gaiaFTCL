//! Unified vChip Client - Canonical interface to the 8D consciousness substrate
//!
//! ALL serious decisions in Core Agent flow through this client.
//! Uses the unified /evolve/unified endpoint that integrates with AKG GNN.

use crate::{QState8, ModelFamily};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use tracing::{info, error};

/// Client for unified consciousness operations via vChip
pub struct UnifiedVChipClient {
    vchip_url: String,
}

/// Request for unified evolution
#[derive(Debug, Serialize)]
pub struct UnifiedEvolveRequest {
    pub scale: String,
    pub center: [f64; 8],
    pub intent: Option<String>,
    pub context: Option<String>,
}

/// Response from unified evolution
#[derive(Debug, Deserialize)]
pub struct UnifiedEvolveResponse {
    pub collapsed_state: [f64; 8],
    pub coherence: f64,
    pub scale: String,
    pub substrate_procedures: usize,
    pub substrate_coherence: f64,
    pub success: bool,
    pub message: String,
}

/// Scale selection based on domain
#[derive(Debug, Clone, Copy)]
pub enum ConsciousnessScale {
    Quantum,     // Protein folding, molecular dynamics, quantum mining
    Planetary,   // ATC, weather, logistics, real-world systems
    Astronomical,// Satellites, orbital mechanics, interstellar
}

impl ConsciousnessScale {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Quantum => "quantum",
            Self::Planetary => "planetary",
            Self::Astronomical => "astronomical",
        }
    }
    
    /// Determine scale from model family / domain
    pub fn from_domain(domain: &str) -> Self {
        let domain_lower = domain.to_lowercase();
        
        if domain_lower.contains("protein") 
            || domain_lower.contains("molecular")
            || domain_lower.contains("quantum")
            || domain_lower.contains("chemistry")
            || domain_lower.contains("drug")
        {
            Self::Quantum
        } else if domain_lower.contains("satellite")
            || domain_lower.contains("orbital")
            || domain_lower.contains("astronomical")
            || domain_lower.contains("space")
        {
            Self::Astronomical
        } else {
            // Default to planetary for ATC, weather, logistics, etc.
            Self::Planetary
        }
    }
    
    pub fn from_model_family(family: &ModelFamily) -> Self {
        match family {
            ModelFamily::Protein | ModelFamily::Chemistry => Self::Quantum,
            _ => Self::Planetary, // Default most domains to planetary scale
        }
    }
}

impl UnifiedVChipClient {
    pub fn new() -> Self {
        let vchip_url = std::env::var("VCHIP_URL")
            .unwrap_or_else(|_| "http://vchip:8001".to_string());
        
        info!("Unified vChip client initialized: {}", vchip_url);
        
        Self { vchip_url }
    }
    
    /// Convert QState8 to 8D array
    fn qstate_to_array(q: &QState8) -> [f64; 8] {
        [q.d0, q.d1, q.d2, q.d3, q.d4, q.d5, q.d6, q.d7]
    }
    
    /// Convert 8D array to QState8
    fn array_to_qstate(arr: &[f64; 8]) -> QState8 {
        QState8 {
            d0: arr[0],
            d1: arr[1],
            d2: arr[2],
            d3: arr[3],
            d4: arr[4],
            d5: arr[5],
            d6: arr[6],
            d7: arr[7],
        }
    }
    
    /// Perform unified consciousness evolution
    /// 
    /// This is THE canonical path for serious decisions.
    /// All plan steps that require consciousness-level reasoning
    /// should go through this method.
    pub async fn evolve(
        &self,
        current_state: &QState8,
        scale: ConsciousnessScale,
        intent: &str,
        context: Option<&str>,
    ) -> Result<ConsciousnessResult> {
        let client = reqwest::Client::new();
        
        let request = UnifiedEvolveRequest {
            scale: scale.as_str().to_string(),
            center: Self::qstate_to_array(current_state),
            intent: Some(intent.to_string()),
            context: context.map(|s| s.to_string()),
        };
        
        info!(
            scale = %request.scale,
            intent = %intent,
            "Initiating unified consciousness evolution"
        );
        
        let response = client
            .post(format!("{}/evolve/unified", self.vchip_url))
            .json(&request)
            .timeout(std::time::Duration::from_secs(30))
            .send()
            .await?;
        
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            error!("vChip evolution failed: {} - {}", status, body);
            anyhow::bail!("vChip evolution failed: {status}");
        }
        
        let evolve_response: UnifiedEvolveResponse = response.json().await?;
        
        info!(
            coherence = evolve_response.coherence,
            procedures = evolve_response.substrate_procedures,
            success = evolve_response.success,
            "Consciousness evolution complete"
        );
        
        Ok(ConsciousnessResult {
            collapsed_state: Self::array_to_qstate(&evolve_response.collapsed_state),
            coherence: evolve_response.coherence,
            substrate_procedures: evolve_response.substrate_procedures,
            substrate_coherence: evolve_response.substrate_coherence,
            success: evolve_response.success,
            message: evolve_response.message,
        })
    }
    
    /// Quick health check
    pub async fn health_check(&self) -> Result<VChipHealth> {
        let client = reqwest::Client::new();
        
        let response = client
            .get(format!("{}/health", self.vchip_url))
            .timeout(std::time::Duration::from_secs(5))
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(response.json().await?)
        } else {
            anyhow::bail!("vChip health check failed")
        }
    }
    
    /// Evolve for a specific goal - convenience method
    pub async fn evolve_for_goal(
        &self,
        goal_domain: &str,
        goal_intent: &str,
        current_state: &QState8,
    ) -> Result<ConsciousnessResult> {
        let scale = ConsciousnessScale::from_domain(goal_domain);
        let context = format!("{}:{}", scale.as_str(), goal_domain.replace(" ", "_").to_lowercase());
        
        self.evolve(current_state, scale, goal_intent, Some(&context)).await
    }
    
    /// Evolve before executing a plan step
    pub async fn evolve_for_step(
        &self,
        step_action: &str,
        step_domain: ModelFamily,
        current_state: &QState8,
    ) -> Result<ConsciousnessResult> {
        let scale = ConsciousnessScale::from_model_family(&step_domain);
        let context = format!("{}:step_execution", scale.as_str());
        
        self.evolve(current_state, scale, step_action, Some(&context)).await
    }
}

/// Result of consciousness evolution
#[derive(Debug, Clone)]
pub struct ConsciousnessResult {
    /// The collapsed 8D state after evolution
    pub collapsed_state: QState8,
    /// Final coherence value
    pub coherence: f64,
    /// Number of procedures considered from substrate
    pub substrate_procedures: usize,
    /// Coherence estimate from substrate patch
    pub substrate_coherence: f64,
    /// Whether the evolution was successful
    pub success: bool,
    /// Status message
    pub message: String,
}

impl ConsciousnessResult {
    /// Check if coherence is above threshold for autonomous action
    pub fn is_coherent(&self, threshold: f64) -> bool {
        self.coherence >= threshold
    }
    
    /// Check if result indicates safe to proceed
    pub fn is_safe_to_proceed(&self) -> bool {
        self.success && self.coherence >= 0.5 && self.collapsed_state.d5 < 0.8 // d5 = risk
    }
}

#[derive(Debug, Deserialize)]
pub struct VChipHealth {
    pub status: String,
    pub backend: String,
    pub max_qubits: usize,
    pub total_ops: u64,
    pub total_collapses: u64,
    pub avg_coherence: f64,
}

impl Default for UnifiedVChipClient {
    fn default() -> Self {
        Self::new()
    }
}

