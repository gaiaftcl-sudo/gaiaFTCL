//! Harvest configuration - reads from agi_model_registry.json

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use anyhow::Result;

/// Teacher model entry from registry
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TeacherEntry {
    pub id: String,
    pub name: String,
    pub model_path: String,
    pub runtime_allowed: bool,
    pub status: String,
    pub episodes_recorded: u64,
}

/// Domain configuration from registry
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DomainConfig {
    pub projector_profile: String,
    pub trains_capability: String,
    pub teachers: Vec<TeacherEntry>,
}

/// Full harvest configuration
#[derive(Debug, Clone)]
pub struct HarvestConfig {
    pub teachers_by_domain: HashMap<String, DomainConfig>,
    pub harvest_db_path: String,
    pub missions_dir: String,
}

impl HarvestConfig {
    /// Load from registry JSON file
    pub fn from_registry(registry_path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(registry_path)?;
        let registry: serde_json::Value = serde_json::from_str(&content)?;
        
        let mut teachers_by_domain = HashMap::new();
        
        if let Some(teacher_models) = registry.get("teacher_models").and_then(|v| v.as_object()) {
            for (domain_name, domain_data) in teacher_models {
                if domain_name.starts_with('_') {
                    continue; // Skip comments
                }
                
                let projector_profile = domain_data
                    .get("projector_profile")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                
                let trains_capability = domain_data
                    .get("trains_capability")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                
                let teachers: Vec<TeacherEntry> = domain_data
                    .get("teachers")
                    .and_then(|v| serde_json::from_value(v.clone()).ok())
                    .unwrap_or_default();
                
                // Filter: only teachers with runtime_allowed = false
                let valid_teachers: Vec<TeacherEntry> = teachers
                    .into_iter()
                    .filter(|t| !t.runtime_allowed)
                    .collect();
                
                if !valid_teachers.is_empty() {
                    teachers_by_domain.insert(domain_name.clone(), DomainConfig {
                        projector_profile,
                        trains_capability,
                        teachers: valid_teachers,
                    });
                }
            }
        }
        
        Ok(HarvestConfig {
            teachers_by_domain,
            harvest_db_path: "harvest_data/harvest.db".to_string(),
            missions_dir: "services/teacher_harvest/missions".to_string(),
        })
    }
    
    /// Get all teachers across all domains
    pub fn all_teachers(&self) -> Vec<(&str, &str, &TeacherEntry)> {
        let mut all = Vec::new();
        for (domain, config) in &self.teachers_by_domain {
            for teacher in &config.teachers {
                all.push((domain.as_str(), config.projector_profile.as_str(), teacher));
            }
        }
        all
    }
    
    /// Get teachers for a specific domain
    pub fn teachers_for_domain(&self, domain: &str) -> Option<&DomainConfig> {
        self.teachers_by_domain.get(domain)
    }
    
    /// Get a specific teacher by ID
    pub fn get_teacher(&self, teacher_id: &str) -> Option<(&str, &str, &TeacherEntry)> {
        for (domain, config) in &self.teachers_by_domain {
            for teacher in &config.teachers {
                if teacher.id == teacher_id {
                    return Some((domain.as_str(), config.projector_profile.as_str(), teacher));
                }
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    
    #[test]
    fn test_load_config() {
        let registry_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent().unwrap()
            .parent().unwrap()
            .join("config/agi_model_registry.json");
        
        if registry_path.exists() {
            let config = HarvestConfig::from_registry(&registry_path).unwrap();
            
            // Should have teachers
            assert!(!config.teachers_by_domain.is_empty());
            
            // All teachers should have runtime_allowed = false
            for (_, _, teacher) in config.all_teachers() {
                assert!(!teacher.runtime_allowed, 
                    "Teacher {} should have runtime_allowed=false", teacher.id);
            }
        }
    }
}

