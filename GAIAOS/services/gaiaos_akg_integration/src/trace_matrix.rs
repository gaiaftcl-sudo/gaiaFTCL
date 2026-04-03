use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceMatrix {
    pub entries: Vec<TraceEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceEntry {
    pub requirement_id: String,
    pub priority: u8,
    pub component: String,
    pub system: String,
    pub test_case: String,
    pub status: String,
}

/// Generate traceability matrix from requirement graph
pub fn generate_trace_matrix(graph: &crate::RequirementGraph) -> TraceMatrix {
    let mut entries = Vec::new();
    
    for node in &graph.nodes {
        if matches!(node.node_type, crate::requirement_graph::NodeType::Requirement) {
            entries.push(TraceEntry {
                requirement_id: node.id.clone(),
                priority: 1,
                component: "TBD".to_string(),
                system: "TBD".to_string(),
                test_case: "TBD".to_string(),
                status: "NOT_TESTED".to_string(),
            });
        }
    }
    
    TraceMatrix { entries }
}

/// Export trace matrix to markdown format
pub fn export_to_markdown(matrix: &TraceMatrix) -> String {
    let mut md = String::from("# Requirements Traceability Matrix\n\n");
    md.push_str("| Req ID | Priority | Component | System | Test Case | Status |\n");
    md.push_str("|--------|----------|-----------|--------|-----------|--------|\n");
    
    for entry in &matrix.entries {
        md.push_str(&format!(
            "| {} | {} | {} | {} | {} | {} |\n",
            entry.requirement_id,
            entry.priority,
            entry.component,
            entry.system,
            entry.test_case,
            entry.status
        ));
    }
    
    md
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_generate_trace_matrix() {
        let graph = crate::requirement_graph::RequirementGraph {
            nodes: vec![],
            edges: vec![],
        };
        
        let matrix = generate_trace_matrix(&graph);
        assert_eq!(matrix.entries.len(), 0);
    }
}
