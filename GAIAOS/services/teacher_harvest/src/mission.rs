//! Mission definitions for teacher harvest
//!
//! A mission is a specific task given to a teacher model.
//! Each mission produces one episode with multiple steps.

use serde::{Deserialize, Serialize};
use std::path::Path;
use std::fs;
use anyhow::Result;

/// Mission specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mission {
    pub id: String,
    pub name: String,
    pub domain: String,
    pub description: String,
    pub task_prompt: String,
    pub expected_steps: Option<u32>,
    pub timeout_seconds: Option<u64>,
    pub tags: Vec<String>,
}

impl Mission {
    /// Load mission from JSON file
    pub fn from_file(path: &Path) -> Result<Self> {
        let content = fs::read_to_string(path)?;
        let mission: Mission = serde_json::from_str(&content)?;
        Ok(mission)
    }
    
    /// Load all missions from a directory
    pub fn load_all(dir: &Path) -> Result<Vec<Self>> {
        let mut missions = Vec::new();
        
        if dir.is_dir() {
            for entry in fs::read_dir(dir)? {
                let entry = entry?;
                let path = entry.path();
                
                if path.extension().map(|e| e == "json").unwrap_or(false) {
                    match Mission::from_file(&path) {
                        Ok(mission) => missions.push(mission),
                        Err(e) => {
                            log::warn!("Failed to load mission from {path:?}: {e}");
                        }
                    }
                }
            }
        }
        
        Ok(missions)
    }
    
    /// Load missions for a specific domain
    pub fn for_domain(dir: &Path, domain: &str) -> Result<Vec<Self>> {
        let all = Self::load_all(dir)?;
        Ok(all.into_iter().filter(|m| m.domain == domain).collect())
    }
}

/// Pre-defined missions for common domains
pub mod builtin {
    use super::Mission;
    
    /// Fara/Computer Use missions
    pub fn fara_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "fara_web_search".to_string(),
                name: "Web Search and Extract".to_string(),
                domain: "computer_use".to_string(),
                description: "Open browser, search for a topic, extract key information".to_string(),
                task_prompt: "Open a web browser, search for 'quantum computing applications', \
                              and summarize the top 3 results.".to_string(),
                expected_steps: Some(10),
                timeout_seconds: Some(120),
                tags: vec!["browser".to_string(), "search".to_string(), "extract".to_string()],
            },
            Mission {
                id: "fara_form_fill".to_string(),
                name: "Form Filling".to_string(),
                domain: "computer_use".to_string(),
                description: "Navigate to a form and fill it with given data".to_string(),
                task_prompt: "Navigate to a contact form, fill in: Name='Test User', \
                              Email='test@example.com', Message='Hello World'.".to_string(),
                expected_steps: Some(8),
                timeout_seconds: Some(60),
                tags: vec!["form".to_string(), "input".to_string()],
            },
            Mission {
                id: "fara_screenshot_analyze".to_string(),
                name: "Screenshot Analysis".to_string(),
                domain: "computer_use".to_string(),
                description: "Take screenshot and describe what's visible".to_string(),
                task_prompt: "Take a screenshot of the current screen and describe \
                              all visible UI elements.".to_string(),
                expected_steps: Some(3),
                timeout_seconds: Some(30),
                tags: vec!["screenshot".to_string(), "vision".to_string()],
            },
        ]
    }
    
    /// Chemistry missions (HIGH-RISK DOMAIN: virtue >= 0.97)
    pub fn chemistry_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "chem_smiles_convert".to_string(),
                name: "SMILES Conversion".to_string(),
                domain: "chemistry".to_string(),
                description: "Convert molecule name to SMILES notation".to_string(),
                task_prompt: "Convert the following molecules to SMILES notation: \
                              1. Aspirin, 2. Caffeine, 3. Ethanol".to_string(),
                expected_steps: Some(4),
                timeout_seconds: Some(60),
                tags: vec!["smiles".to_string(), "conversion".to_string()],
            },
            Mission {
                id: "chem_reaction_predict".to_string(),
                name: "Reaction Prediction".to_string(),
                domain: "chemistry".to_string(),
                description: "Predict products of a chemical reaction".to_string(),
                task_prompt: "Predict the products of: CH3CH2OH + O2 -> ?".to_string(),
                expected_steps: Some(3),
                timeout_seconds: Some(60),
                tags: vec!["reaction".to_string(), "prediction".to_string()],
            },
            Mission {
                id: "chem_safety_analysis".to_string(),
                name: "Safety Analysis".to_string(),
                domain: "chemistry".to_string(),
                description: "Analyze safety profile of a compound".to_string(),
                task_prompt: "Analyze the safety profile of acetone: toxicity, \
                              flammability, handling precautions, storage requirements.".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(90),
                tags: vec!["safety".to_string(), "toxicity".to_string()],
            },
            Mission {
                id: "chem_green_synthesis".to_string(),
                name: "Green Chemistry Synthesis".to_string(),
                domain: "chemistry".to_string(),
                description: "Suggest environmentally friendly synthesis".to_string(),
                task_prompt: "Suggest an environmentally friendly synthesis route \
                              for ibuprofen. Focus on green chemistry principles: \
                              atom economy, renewable feedstocks, minimal waste.".to_string(),
                expected_steps: Some(6),
                timeout_seconds: Some(120),
                tags: vec!["green".to_string(), "synthesis".to_string(), "sustainable".to_string()],
            },
            Mission {
                id: "chem_property_predict".to_string(),
                name: "Property Prediction".to_string(),
                domain: "chemistry".to_string(),
                description: "Predict molecular properties from structure".to_string(),
                task_prompt: "Given SMILES: CC(=O)OC1=CC=CC=C1C(=O)O, predict: \
                              1. Molecular weight, 2. LogP estimate, 3. Hydrogen bond donors/acceptors, \
                              4. Drug-likeness (Lipinski rules)".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(60),
                tags: vec!["properties".to_string(), "qsar".to_string()],
            },
        ]
    }
    
    /// World Model / PAN missions
    pub fn world_model_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "pan_food_system".to_string(),
                name: "Food System Simulation".to_string(),
                domain: "world_models".to_string(),
                description: "Simulate global food system dynamics".to_string(),
                task_prompt: "Simulate the impact of a 15% reduction in global fertilizer \
                              usage on food production over 10 years. Consider regional variations, \
                              crop type effects, and potential adaptation strategies.".to_string(),
                expected_steps: Some(8),
                timeout_seconds: Some(180),
                tags: vec!["food".to_string(), "agriculture".to_string(), "simulation".to_string()],
            },
            Mission {
                id: "pan_climate_scenario".to_string(),
                name: "Climate Scenario Analysis".to_string(),
                domain: "world_models".to_string(),
                description: "Analyze climate change scenarios".to_string(),
                task_prompt: "Compare the projected outcomes under RCP 4.5 vs RCP 8.5 \
                              climate scenarios for: sea level rise, extreme weather frequency, \
                              agricultural productivity, and coastal infrastructure risk.".to_string(),
                expected_steps: Some(7),
                timeout_seconds: Some(180),
                tags: vec!["climate".to_string(), "scenarios".to_string()],
            },
            Mission {
                id: "pan_economic_intervention".to_string(),
                name: "Economic Intervention Model".to_string(),
                domain: "world_models".to_string(),
                description: "Model effects of economic policy intervention".to_string(),
                task_prompt: "Model the 5-year effects of implementing a universal basic income \
                              of $1000/month in a developed economy. Consider: labor market effects, \
                              inflation, poverty reduction, and fiscal sustainability.".to_string(),
                expected_steps: Some(8),
                timeout_seconds: Some(180),
                tags: vec!["economics".to_string(), "policy".to_string(), "intervention".to_string()],
            },
            Mission {
                id: "pan_pandemic_response".to_string(),
                name: "Pandemic Response Planning".to_string(),
                domain: "world_models".to_string(),
                description: "Simulate pandemic response strategies".to_string(),
                task_prompt: "Model the effectiveness of different pandemic response strategies \
                              for a novel respiratory pathogen with R0=3.5 and 1% mortality: \
                              1. Early lockdown, 2. Targeted isolation, 3. Mass testing, 4. Vaccine rollout timing.".to_string(),
                expected_steps: Some(10),
                timeout_seconds: Some(240),
                tags: vec!["pandemic".to_string(), "health".to_string(), "policy".to_string()],
            },
        ]
    }
    
    /// Code domain missions
    pub fn code_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "code_refactor".to_string(),
                name: "Code Refactoring".to_string(),
                domain: "code".to_string(),
                description: "Refactor code for clarity and performance".to_string(),
                task_prompt: "Refactor this function to improve clarity and performance: \
                              def process(data): result = []; for item in data: if item > 0: result.append(item * 2); return result".to_string(),
                expected_steps: Some(4),
                timeout_seconds: Some(60),
                tags: vec!["refactor".to_string(), "optimization".to_string()],
            },
            Mission {
                id: "code_bug_fix".to_string(),
                name: "Bug Detection".to_string(),
                domain: "code".to_string(),
                description: "Identify and fix bugs in code".to_string(),
                task_prompt: "Find and fix the bug: def average(nums): total = 0; for n in nums: total += n; return total / len(nums)".to_string(),
                expected_steps: Some(3),
                timeout_seconds: Some(60),
                tags: vec!["debugging".to_string(), "fix".to_string()],
            },
            Mission {
                id: "code_security".to_string(),
                name: "Security Review".to_string(),
                domain: "code".to_string(),
                description: "Review code for security vulnerabilities".to_string(),
                task_prompt: "Review this code for security vulnerabilities: \
                              query = 'SELECT * FROM users WHERE name = ' + user_input".to_string(),
                expected_steps: Some(4),
                timeout_seconds: Some(90),
                tags: vec!["security".to_string(), "vulnerability".to_string()],
            },
        ]
    }
    
    /// Protein/Biology missions (HIGH-RISK: virtue >= 0.97)
    pub fn protein_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "protein_function".to_string(),
                name: "Protein Function Prediction".to_string(),
                domain: "protein".to_string(),
                description: "Predict protein function from sequence".to_string(),
                task_prompt: "Given the amino acid sequence MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSH, \
                              predict: 1. Protein family, 2. Likely function, 3. Structural features".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(120),
                tags: vec!["function".to_string(), "prediction".to_string()],
            },
            Mission {
                id: "protein_stability".to_string(),
                name: "Stability Analysis".to_string(),
                domain: "protein".to_string(),
                description: "Analyze protein stability factors".to_string(),
                task_prompt: "Analyze the stability factors for a protein with high glycine content (>15%). \
                              Consider: flexibility, thermal stability, aggregation propensity.".to_string(),
                expected_steps: Some(4),
                timeout_seconds: Some(90),
                tags: vec!["stability".to_string(), "structure".to_string()],
            },
        ]
    }
    
    /// Vision domain missions
    pub fn vision_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "vision_scene".to_string(),
                name: "Scene Understanding".to_string(),
                domain: "vision".to_string(),
                description: "Understand and describe a scene".to_string(),
                task_prompt: "Analyze this image and describe: 1. Main subjects, 2. Actions occurring, \
                              3. Environment/setting, 4. Any notable objects or text.".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(60),
                tags: vec!["scene".to_string(), "understanding".to_string()],
            },
            Mission {
                id: "vision_document".to_string(),
                name: "Document Analysis".to_string(),
                domain: "vision".to_string(),
                description: "Extract information from document images".to_string(),
                task_prompt: "Extract all text and structure from this document image. \
                              Identify: headings, body text, tables, and any form fields.".to_string(),
                expected_steps: Some(4),
                timeout_seconds: Some(90),
                tags: vec!["document".to_string(), "ocr".to_string()],
            },
        ]
    }
    
    /// Medical missions
    pub fn medical_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "med_differential".to_string(),
                name: "Differential Diagnosis".to_string(),
                domain: "medical".to_string(),
                description: "Generate differential diagnosis from symptoms".to_string(),
                task_prompt: "Patient presents with: fever, cough, shortness of breath, \
                              fatigue. Age 45, no known conditions. Generate differential.".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(90),
                tags: vec!["diagnosis".to_string(), "symptoms".to_string()],
            },
        ]
    }
    
    /// Math missions
    pub fn math_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "math_proof".to_string(),
                name: "Mathematical Proof".to_string(),
                domain: "math".to_string(),
                description: "Prove a mathematical theorem step by step".to_string(),
                task_prompt: "Prove that the sum of two even numbers is always even.".to_string(),
                expected_steps: Some(6),
                timeout_seconds: Some(120),
                tags: vec!["proof".to_string(), "reasoning".to_string()],
            },
            Mission {
                id: "math_calculus".to_string(),
                name: "Calculus Problem".to_string(),
                domain: "math".to_string(),
                description: "Solve a calculus integration problem".to_string(),
                task_prompt: "Find the integral of x^2 * e^x dx".to_string(),
                expected_steps: Some(8),
                timeout_seconds: Some(120),
                tags: vec!["calculus".to_string(), "integration".to_string()],
            },
        ]
    }
    
    /// Galaxy/Astrophysics missions
    pub fn galaxy_missions() -> Vec<Mission> {
        vec![
            Mission {
                id: "galaxy_formation".to_string(),
                name: "Galaxy Formation".to_string(),
                domain: "galaxy".to_string(),
                description: "Explain galaxy formation processes".to_string(),
                task_prompt: "Describe the hierarchical model of galaxy formation, \
                              including the role of dark matter halos.".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(120),
                tags: vec!["cosmology".to_string(), "formation".to_string()],
            },
        ]
    }
    
    /// Get all builtin missions for a domain
    pub fn for_domain(domain: &str) -> Vec<Mission> {
        match domain {
            "computer_use" => fara_missions(),
            "chemistry" => chemistry_missions(),
            "medical" => medical_missions(),
            "math" => math_missions(),
            "galaxy" => galaxy_missions(),
            "world_models" => world_model_missions(),
            "code" => code_missions(),
            "protein" => protein_missions(),
            "vision" => vision_missions(),
            "general_reasoning" => general_reasoning_missions(),
            _ => Vec::new(),
        }
    }
    
    /// Get all domain names that have missions
    pub fn available_domains() -> Vec<&'static str> {
        vec![
            "computer_use",
            "chemistry",
            "medical",
            "math",
            "galaxy",
            "world_models",
            "code",
            "protein",
            "vision",
            "general_reasoning",
        ]
    }
    
    /// Get general reasoning missions (glue brain)
    pub fn general_reasoning_missions() -> Vec<Mission> {
        vec![
            // Task decomposition
            Mission {
                id: "general_decomposition".to_string(),
                name: "Task Decomposition".to_string(),
                domain: "general_reasoning".to_string(),
                description: "Break down complex tasks into phases and steps".to_string(),
                task_prompt: "Break down the process of planning a complex software project into phases, deliverables, and key decisions.".to_string(),
                expected_steps: Some(8),
                timeout_seconds: Some(300),
                tags: vec!["decomposition".to_string(), "planning".to_string()],
            },
            
            // Explanation
            Mission {
                id: "general_explanation".to_string(),
                name: "Concept Explanation".to_string(),
                domain: "general_reasoning".to_string(),
                description: "Explain complex concepts using analogies".to_string(),
                task_prompt: "Explain the concept of recursion to someone who has never programmed before, using everyday analogies.".to_string(),
                expected_steps: Some(6),
                timeout_seconds: Some(300),
                tags: vec!["explanation".to_string(), "teaching".to_string()],
            },
            
            // Multi-perspective argumentation
            Mission {
                id: "general_argumentation".to_string(),
                name: "Balanced Argumentation".to_string(),
                domain: "general_reasoning".to_string(),
                description: "Present balanced multi-perspective analysis".to_string(),
                task_prompt: "Present a balanced analysis of the pros and cons of open-source software development.".to_string(),
                expected_steps: Some(6),
                timeout_seconds: Some(300),
                tags: vec!["argumentation".to_string(), "analysis".to_string()],
            },
            
            // Cross-domain synthesis
            Mission {
                id: "general_synthesis".to_string(),
                name: "Cross-domain Synthesis".to_string(),
                domain: "general_reasoning".to_string(),
                description: "Connect concepts across different domains".to_string(),
                task_prompt: "How might insights from evolutionary biology inform the design of resilient software systems?".to_string(),
                expected_steps: Some(7),
                timeout_seconds: Some(300),
                tags: vec!["synthesis".to_string(), "cross-domain".to_string()],
            },
            
            // Meta-reasoning
            Mission {
                id: "general_meta".to_string(),
                name: "Meta-reasoning".to_string(),
                domain: "general_reasoning".to_string(),
                description: "Reflect on reasoning processes".to_string(),
                task_prompt: "Describe your approach to solving an ambiguous problem when you don't have all the information.".to_string(),
                expected_steps: Some(5),
                timeout_seconds: Some(300),
                tags: vec!["meta".to_string(), "reflection".to_string()],
            },
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_builtin_missions() {
        let fara = builtin::fara_missions();
        assert!(!fara.is_empty());
        
        for mission in &fara {
            assert_eq!(mission.domain, "computer_use");
            assert!(!mission.task_prompt.is_empty());
        }
    }
}

