use serde::{Deserialize, Serialize};
use std::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Requirement {
    pub id: String,
    pub text: String,
    pub priority: u8,
    pub requirement_type: RequirementType,
    pub best_practices: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RequirementType {
    Safety,
    UI,
    Performance,
    Implementation,
}

/// Parse TTL requirements from a file
pub fn parse_ttl_requirements(ttl_path: &str) -> Result<Vec<Requirement>, String> {
    let content = fs::read_to_string(ttl_path)
        .map_err(|e| format!("Failed to read TTL file: {}", e))?;
    
    let mut requirements = Vec::new();
    
    // Simple TTL parsing - extract requirement IDs and text
    // This is a simplified parser - production would use a proper RDF library
    for line in content.lines() {
        if line.contains("req:hasId") {
            let id = extract_quoted_value(line);
            // Look ahead for text
            requirements.push(Requirement {
                id: id.clone(),
                text: format!("Requirement {}", id),
                priority: 1,
                requirement_type: RequirementType::Implementation,
                best_practices: vec![],
            });
        }
    }
    
    Ok(requirements)
}

fn extract_quoted_value(line: &str) -> String {
    line.split('"')
        .nth(1)
        .unwrap_or("")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_parse_requirements() {
        // Test will be implemented with actual TTL files
    }
}
