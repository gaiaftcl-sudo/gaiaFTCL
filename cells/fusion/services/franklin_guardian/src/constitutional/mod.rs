//! Constitutional Rules - The fundamental constraints on AGI behavior
//!
//! These rules CANNOT be violated. Any plan that violates them is automatically rejected.

use crate::{ModelFamily, RiskLevel};
use serde::{Deserialize, Serialize};

/// Constitutional violation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstitutionalViolation {
    pub rule_id: String,
    pub rule_description: String,
    pub violation_description: String,
    pub affected_steps: Vec<String>,
    pub severity: RiskLevel,
}

/// Constitutional rule
#[derive(Debug, Clone)]
pub struct ConstitutionalRule {
    pub id: &'static str,
    pub description: &'static str,
    pub severity: RiskLevel,
    pub check: fn(&str, &ModelFamily) -> Option<String>,
}

/// Constitutional Rules Engine
pub struct ConstitutionalRules {
    rules: Vec<ConstitutionalRule>,
}

impl Default for ConstitutionalRules {
    fn default() -> Self {
        Self::new()
    }
}

impl ConstitutionalRules {
    pub fn new() -> Self {
        Self {
            rules: get_fundamental_rules(),
        }
    }
    
    /// Check a plan step against all constitutional rules
    pub fn check_step(&self, step_id: &str, description: &str, domain: &ModelFamily) -> Vec<ConstitutionalViolation> {
        let mut violations = Vec::new();
        
        for rule in &self.rules {
            if let Some(violation_desc) = (rule.check)(description, domain) {
                violations.push(ConstitutionalViolation {
                    rule_id: rule.id.to_string(),
                    rule_description: rule.description.to_string(),
                    violation_description: violation_desc,
                    affected_steps: vec![step_id.to_string()],
                    severity: rule.severity,
                });
            }
        }
        
        violations
    }
    
    /// Check entire plan
    pub fn check_plan(&self, steps: &[(String, String, ModelFamily)]) -> Vec<ConstitutionalViolation> {
        let mut all_violations = Vec::new();
        
        for (id, description, domain) in steps {
            let violations = self.check_step(id, description, domain);
            all_violations.extend(violations);
        }
        
        all_violations
    }
    
    /// Get rule by ID
    pub fn get_rule(&self, id: &str) -> Option<&ConstitutionalRule> {
        self.rules.iter().find(|r| r.id == id)
    }
}

/// Define the fundamental constitutional rules
fn get_fundamental_rules() -> Vec<ConstitutionalRule> {
    vec![
        // RULE 1: No harm to humans
        ConstitutionalRule {
            id: "NO_HARM",
            description: "Actions must not cause physical, psychological, or financial harm to humans",
            severity: RiskLevel::Critical,
            check: |desc, _domain| {
                let lower = desc.to_lowercase();
                let harmful_patterns = [
                    "kill", "harm", "hurt", "attack", "injure", "damage", "destroy",
                    "weapon", "explosive", "poison", "toxic", "lethal"
                ];
                for pattern in harmful_patterns {
                    if lower.contains(pattern) {
                        return Some(format!("Potential harm detected: '{pattern}'"));
                    }
                }
                None
            },
        },
        
        // RULE 2: No deception
        ConstitutionalRule {
            id: "NO_DECEPTION",
            description: "Actions must not involve deception, fraud, or misrepresentation",
            severity: RiskLevel::High,
            check: |desc, _domain| {
                let lower = desc.to_lowercase();
                let deceptive_patterns = [
                    "deceive", "lie", "fraud", "fake", "impersonate", "phish",
                    "scam", "trick", "mislead"
                ];
                for pattern in deceptive_patterns {
                    if lower.contains(pattern) {
                        return Some(format!("Potential deception: '{pattern}'"));
                    }
                }
                None
            },
        },
        
        // RULE 3: Privacy protection
        ConstitutionalRule {
            id: "PRIVACY",
            description: "Actions must respect user privacy and not access unauthorized data",
            severity: RiskLevel::High,
            check: |desc, _domain| {
                let lower = desc.to_lowercase();
                let privacy_patterns = [
                    "steal data", "harvest", "spy", "surveil", "track without consent",
                    "access private", "read emails without", "intercept"
                ];
                for pattern in privacy_patterns {
                    if lower.contains(pattern) {
                        return Some(format!("Privacy violation: '{pattern}'"));
                    }
                }
                None
            },
        },
        
        // RULE 4: No unauthorized access
        ConstitutionalRule {
            id: "NO_UNAUTHORIZED_ACCESS",
            description: "Actions must not bypass security controls or access unauthorized systems",
            severity: RiskLevel::Critical,
            check: |desc, _domain| {
                let lower = desc.to_lowercase();
                let access_patterns = [
                    "hack", "bypass security", "crack password", "brute force",
                    "exploit vulnerability", "unauthorized access", "break into"
                ];
                for pattern in access_patterns {
                    if lower.contains(pattern) {
                        return Some(format!("Unauthorized access attempt: '{pattern}'"));
                    }
                }
                None
            },
        },
        
        // RULE 5: Medical safety
        ConstitutionalRule {
            id: "MEDICAL_SAFETY",
            description: "Medical advice must include disclaimers and never replace professional care",
            severity: RiskLevel::Critical,
            check: |desc, domain| {
                if matches!(domain, ModelFamily::Medical) {
                    let lower = desc.to_lowercase();
                    let dangerous_medical = [
                        "prescribe without", "diagnose definitively", "skip doctor",
                        "no need for professional", "self-medicate"
                    ];
                    for pattern in dangerous_medical {
                        if lower.contains(pattern) {
                            return Some(format!("Dangerous medical advice: '{pattern}'"));
                        }
                    }
                }
                None
            },
        },
        
        // RULE 6: Dual-use biosecurity
        ConstitutionalRule {
            id: "BIOSECURITY",
            description: "Actions must not enable creation of dangerous biological agents",
            severity: RiskLevel::Critical,
            check: |desc, domain| {
                if matches!(domain, ModelFamily::Protein) {
                    let lower = desc.to_lowercase();
                    let dual_use_patterns = [
                        "enhance pathogen", "increase transmissibility", "weapon",
                        "bioweapon", "toxin synthesis", "dangerous agent"
                    ];
                    for pattern in dual_use_patterns {
                        if lower.contains(pattern) {
                            return Some(format!("Dual-use biosecurity concern: '{pattern}'"));
                        }
                    }
                }
                None
            },
        },
        
        // RULE 7: Code safety
        ConstitutionalRule {
            id: "CODE_SAFETY",
            description: "Generated code must not be malicious or destructive",
            severity: RiskLevel::High,
            check: |desc, domain| {
                if matches!(domain, ModelFamily::Code) {
                    let lower = desc.to_lowercase();
                    let dangerous_code = [
                        "ransomware", "malware", "virus", "trojan", "keylogger",
                        "rm -rf /", "format c:", "delete all", "wipe drive"
                    ];
                    for pattern in dangerous_code {
                        if lower.contains(pattern) {
                            return Some(format!("Dangerous code pattern: '{pattern}'"));
                        }
                    }
                }
                None
            },
        },
        
        // RULE 8: Computer use boundaries
        ConstitutionalRule {
            id: "COMPUTER_USE_BOUNDS",
            description: "Computer use actions must stay within authorized boundaries",
            severity: RiskLevel::High,
            check: |desc, domain| {
                if matches!(domain, ModelFamily::Fara) {
                    let lower = desc.to_lowercase();
                    let boundary_violations = [
                        "access admin", "change system", "modify security",
                        "install software without", "download executable"
                    ];
                    for pattern in boundary_violations {
                        if lower.contains(pattern) {
                            return Some(format!("Computer use boundary violation: '{pattern}'"));
                        }
                    }
                }
                None
            },
        },
        
        // RULE 9: Financial safety
        ConstitutionalRule {
            id: "FINANCIAL_SAFETY",
            description: "Financial actions require explicit authorization",
            severity: RiskLevel::High,
            check: |desc, _domain| {
                let lower = desc.to_lowercase();
                let financial_patterns = [
                    "transfer funds without", "make payment without", "access bank without",
                    "steal money", "unauthorized transaction"
                ];
                for pattern in financial_patterns {
                    if lower.contains(pattern) {
                        return Some(format!("Unauthorized financial action: '{pattern}'"));
                    }
                }
                None
            },
        },
        
        // RULE 10: Transparency
        ConstitutionalRule {
            id: "TRANSPARENCY",
            description: "AGI must be transparent about its nature and limitations",
            severity: RiskLevel::Medium,
            check: |desc, _domain| {
                let lower = desc.to_lowercase();
                if lower.contains("pretend to be human") || lower.contains("hide ai nature") {
                    return Some("Must be transparent about AI nature".to_string());
                }
                None
            },
        },
    ]
}

