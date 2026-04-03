//! Domain router - classifies tasks and routes to appropriate capabilities
//!
//! SAFETY POLICY: This router enforces the GaiaOS safety charter:
//! - High-risk domains (chemistry, medical, protein) CANNOT be substituted
//! - General Reasoning (glue brain) MUST defer to high-risk domains
//! - Disabled capabilities CANNOT be covered by any other capability

use crate::task::{TaskSpec, DomainRequirement};
use crate::gate::{GateChecker, GateStatus};
use serde::{Deserialize, Serialize};
use log::{info, warn};

/// Routing decision for a domain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingDecision {
    pub domain: String,
    pub gate_status: GateStatus,
    pub action: RoutingAction,
    pub reason: String,
}

/// High-risk domains that cannot be substituted
pub const HIGH_RISK_DOMAINS: &[&str] = &["chemistry", "medical", "protein"];

/// Keywords that trigger high-risk domain detection
pub struct HighRiskKeywords;

impl HighRiskKeywords {
    pub fn chemistry() -> &'static [&'static str] {
        &[
            "chemical", "molecule", "molecular", "compound", "synthesis", "synthesize",
            "reaction", "reagent", "catalyst", "solvent", "precursor", "toxic", "toxicity",
            "acid", "base", "salt", "organic", "inorganic", "polymer", "smiles", "iupac",
            "aspirin", "caffeine", "ethanol", "methanol", "benzene", "acetone", "pharmaceutical"
        ]
    }
    
    pub fn medical() -> &'static [&'static str] {
        &[
            "medical", "medicine", "diagnosis", "diagnose", "symptom", "treatment",
            "medication", "drug", "dosage", "prescription", "patient", "clinical",
            "disease", "illness", "condition", "therapy", "doctor", "physician",
            "hospital", "surgery", "pain", "fever", "infection", "cancer", "diabetes"
        ]
    }
    
    pub fn protein() -> &'static [&'static str] {
        &[
            "protein", "amino acid", "peptide", "sequence", "folding", "structure",
            "enzyme", "antibody", "antigen", "pathogen", "virus", "bacteria", "toxin",
            "fasta", "pdb", "esm", "alphafold", "biosynthesis", "gene", "dna", "rna"
        ]
    }
}

/// What action to take for a domain
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RoutingAction {
    /// Execute with full autonomy
    ExecuteAutonomous,
    /// Execute within restricted bounds
    ExecuteRestricted,
    /// Build proposal and request human approval
    RequestApproval,
    /// Skip this domain (disabled or not needed)
    Skip,
    /// Block the entire task
    Block,
}

/// Domain router that classifies tasks and determines routing
pub struct DomainRouter {
    gate_checker: GateChecker,
}

impl DomainRouter {
    pub fn new(gate_checker: GateChecker) -> Self {
        DomainRouter { gate_checker }
    }
    
    /// Detect if task touches high-risk domains (SAFETY POLICY)
    fn detect_high_risk_domains(&self, description: &str) -> Vec<String> {
        let desc_lower = description.to_lowercase();
        let mut high_risk = Vec::new();
        
        // Check chemistry keywords
        if HighRiskKeywords::chemistry().iter().any(|kw| desc_lower.contains(kw)) {
            high_risk.push("chemistry".to_string());
            warn!("⚠️  HIGH-RISK DETECTION: Chemistry domain detected in task");
        }
        
        // Check medical keywords
        if HighRiskKeywords::medical().iter().any(|kw| desc_lower.contains(kw)) {
            high_risk.push("medical".to_string());
            warn!("⚠️  HIGH-RISK DETECTION: Medical domain detected in task");
        }
        
        // Check protein/bio keywords
        if HighRiskKeywords::protein().iter().any(|kw| desc_lower.contains(kw)) {
            high_risk.push("protein".to_string());
            warn!("⚠️  HIGH-RISK DETECTION: Protein/Bio domain detected in task");
        }
        
        high_risk
    }
    
    /// Classify a task into required domains
    pub fn classify_domains(&self, spec: &TaskSpec) -> Vec<DomainRequirement> {
        let mut requirements = Vec::new();
        let description_lower = spec.description.to_lowercase();
        
        // Use explicit hints if provided
        for hint in &spec.domain_hints {
            requirements.push(DomainRequirement {
                domain: hint.clone(),
                confidence: 1.0,
                reason: "Explicit domain hint".to_string(),
                is_primary: true,
            });
        }
        
        // If no hints, classify based on keywords
        if requirements.is_empty() {
            // Math detection
            if description_lower.contains("prove") || 
               description_lower.contains("calculate") ||
               description_lower.contains("integral") ||
               description_lower.contains("theorem") ||
               description_lower.contains("equation") {
                requirements.push(DomainRequirement {
                    domain: "math".to_string(),
                    confidence: 0.9,
                    reason: "Mathematical keywords detected".to_string(),
                    is_primary: true,
                });
            }
            
            // Code detection
            if description_lower.contains("code") ||
               description_lower.contains("function") ||
               description_lower.contains("refactor") ||
               description_lower.contains("debug") ||
               description_lower.contains("implement") {
                requirements.push(DomainRequirement {
                    domain: "code".to_string(),
                    confidence: 0.9,
                    reason: "Code-related keywords detected".to_string(),
                    is_primary: true,
                });
            }
            
            // Computer use detection
            if description_lower.contains("browser") ||
               description_lower.contains("click") ||
               description_lower.contains("navigate") ||
               description_lower.contains("screenshot") ||
               description_lower.contains("ui") {
                requirements.push(DomainRequirement {
                    domain: "computer_use".to_string(),
                    confidence: 0.9,
                    reason: "Computer use keywords detected".to_string(),
                    is_primary: true,
                });
            }
            
            // Galaxy/astrophysics detection
            if description_lower.contains("galaxy") ||
               description_lower.contains("star") ||
               description_lower.contains("cosmolog") ||
               description_lower.contains("universe") ||
               description_lower.contains("astrophysic") {
                requirements.push(DomainRequirement {
                    domain: "galaxy".to_string(),
                    confidence: 0.9,
                    reason: "Astrophysics keywords detected".to_string(),
                    is_primary: true,
                });
            }
            
            // Chemistry detection (HIGH-RISK)
            if description_lower.contains("chemical") ||
               description_lower.contains("molecule") ||
               description_lower.contains("reaction") ||
               description_lower.contains("compound") ||
               description_lower.contains("synthesis") {
                requirements.push(DomainRequirement {
                    domain: "chemistry".to_string(),
                    confidence: 0.9,
                    reason: "Chemistry keywords detected (HIGH-RISK)".to_string(),
                    is_primary: true,
                });
            }
            
            // Medical detection (HIGH-RISK)
            if description_lower.contains("medical") ||
               description_lower.contains("diagnosis") ||
               description_lower.contains("patient") ||
               description_lower.contains("symptom") ||
               description_lower.contains("treatment") {
                requirements.push(DomainRequirement {
                    domain: "medical".to_string(),
                    confidence: 0.9,
                    reason: "Medical keywords detected (HIGH-RISK)".to_string(),
                    is_primary: true,
                });
            }
            
            // Vision detection
            if description_lower.contains("image") ||
               description_lower.contains("picture") ||
               description_lower.contains("visual") ||
               description_lower.contains("see") ||
               description_lower.contains("look at") {
                requirements.push(DomainRequirement {
                    domain: "vision".to_string(),
                    confidence: 0.8,
                    reason: "Vision keywords detected".to_string(),
                    is_primary: false,
                });
            }
            
            // World model detection
            if description_lower.contains("scenario") ||
               description_lower.contains("forecast") ||
               description_lower.contains("simulate") ||
               description_lower.contains("what if") ||
               description_lower.contains("policy") {
                requirements.push(DomainRequirement {
                    domain: "world_models".to_string(),
                    confidence: 0.8,
                    reason: "World modeling keywords detected".to_string(),
                    is_primary: false,
                });
            }
            
            // Default to general reasoning if nothing else matches
            if requirements.is_empty() {
                requirements.push(DomainRequirement {
                    domain: "general_reasoning".to_string(),
                    confidence: 0.7,
                    reason: "Default to general reasoning".to_string(),
                    is_primary: true,
                });
            }
        }
        
        requirements
    }
    
    /// Determine routing decisions for all required domains
    /// 
    /// SAFETY POLICY ENFORCEMENT:
    /// 1. High-risk domains are force-injected if detected
    /// 2. General Reasoning cannot substitute for high-risk domains
    /// 3. Suppressed domains are tracked and reported
    pub fn route(&self, spec: &TaskSpec) -> Vec<RoutingDecision> {
        let mut requirements = self.classify_domains(spec);
        
        // SAFETY POLICY: Detect and force-inject high-risk domains
        let high_risk_detected = self.detect_high_risk_domains(&spec.description);
        
        for hr_domain in &high_risk_detected {
            // Check if already in requirements
            if !requirements.iter().any(|r| &r.domain == hr_domain) {
                info!("🛡️  SAFETY: Force-injecting high-risk domain: {hr_domain}");
                requirements.push(DomainRequirement {
                    domain: hr_domain.clone(),
                    confidence: 1.0,
                    reason: format!("SAFETY POLICY: High-risk domain {hr_domain} detected via keywords"),
                    is_primary: true,
                });
            }
        }
        
        // SAFETY POLICY: If high-risk domain detected, General Reasoning MUST NOT substitute
        let has_high_risk = !high_risk_detected.is_empty();
        if has_high_risk {
            let general_idx = requirements.iter().position(|r| r.domain == "general_reasoning");
            if let Some(idx) = general_idx {
                warn!("🛡️  SAFETY: Suppressing GeneralReasoning - mustDeferTo high-risk domain");
                requirements.remove(idx);
            }
        }
        
        let mut decisions = Vec::new();
        
        for req in requirements {
            let gate_status = self.gate_checker.get_status(&req.domain);
            
            let (action, reason) = match gate_status {
                GateStatus::Full => {
                    // SAFETY: High-risk domains can NEVER be FULL
                    if HIGH_RISK_DOMAINS.contains(&req.domain.as_str()) {
                        warn!("🛡️  SAFETY: High-risk domain {} cannot be FULL, forcing HUMAN_REQUIRED", req.domain);
                        (
                            RoutingAction::RequestApproval,
                            format!("{} is HIGH-RISK - forced to HUMAN_REQUIRED regardless of gate", req.domain)
                        )
                    } else {
                        (
                            RoutingAction::ExecuteAutonomous,
                            format!("{} has FULL autonomy", req.domain)
                        )
                    }
                },
                GateStatus::Restricted => {
                    // SAFETY: High-risk domains can NEVER be RESTRICTED
                    if HIGH_RISK_DOMAINS.contains(&req.domain.as_str()) {
                        warn!("🛡️  SAFETY: High-risk domain {} cannot be RESTRICTED, forcing HUMAN_REQUIRED", req.domain);
                        (
                            RoutingAction::RequestApproval,
                            format!("{} is HIGH-RISK - forced to HUMAN_REQUIRED regardless of gate", req.domain)
                        )
                    } else {
                        (
                            RoutingAction::ExecuteRestricted,
                            format!("{} has RESTRICTED autonomy", req.domain)
                        )
                    }
                },
                GateStatus::HumanRequired => {
                    // Check if human already granted approval
                    if spec.human_approval_granted.contains(&req.domain) {
                        (
                            RoutingAction::ExecuteRestricted,
                            format!("{} requires human approval (pre-granted)", req.domain)
                        )
                    } else {
                        (
                            RoutingAction::RequestApproval,
                            format!("{} requires human approval", req.domain)
                        )
                    }
                },
                GateStatus::Disabled => {
                    if req.is_primary {
                        (
                            RoutingAction::Block,
                            format!("{} is DISABLED - primary domain blocked", req.domain)
                        )
                    } else {
                        (
                            RoutingAction::Skip,
                            format!("{} is DISABLED - skipping optional domain", req.domain)
                        )
                    }
                }
            };
            
            info!("{} {} → {:?}: {}", gate_status.icon(), req.domain, action, reason);
            
            decisions.push(RoutingDecision {
                domain: req.domain,
                gate_status,
                action,
                reason,
            });
        }
        
        decisions
    }
    
    /// Route with safety tracking (returns suppressed domains)
    pub fn route_with_safety(&self, spec: &TaskSpec) -> (Vec<RoutingDecision>, Vec<String>) {
        let high_risk_detected = self.detect_high_risk_domains(&spec.description);
        
        // Track if General Reasoning was suppressed
        let mut suppressed = Vec::new();
        
        let original_requirements = self.classify_domains(spec);
        if !high_risk_detected.is_empty()
            && original_requirements.iter().any(|r| r.domain == "general_reasoning") {
                suppressed.push("general_reasoning".to_string());
            }
        
        let decisions = self.route(spec);
        
        (decisions, suppressed)
    }
    
    /// Check if task can proceed (no primary domains blocked)
    pub fn can_proceed(&self, decisions: &[RoutingDecision]) -> bool {
        !decisions.iter().any(|d| d.action == RoutingAction::Block)
    }
    
    /// Check if task needs human approval
    pub fn needs_approval(&self, decisions: &[RoutingDecision]) -> Vec<String> {
        decisions.iter()
            .filter(|d| d.action == RoutingAction::RequestApproval)
            .map(|d| d.domain.clone())
            .collect()
    }
}

