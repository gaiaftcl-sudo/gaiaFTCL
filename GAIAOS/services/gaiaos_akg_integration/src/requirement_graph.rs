use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequirementGraph {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphNode {
    pub id: String,
    pub node_type: NodeType,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NodeType {
    Requirement,
    Plugin,
    System,
    Component,
    BestPractice,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphEdge {
    pub from: String,
    pub to: String,
    pub edge_type: EdgeType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EdgeType {
    ImplementedBy,
    ContainsSystem,
    UsesComponent,
    EnforcedByPractice,
}

/// Build requirement graph from parsed requirements
pub fn build_requirement_graph(requirements: Vec<crate::Requirement>) -> RequirementGraph {
    let mut nodes = Vec::new();
    let edges = Vec::new();
    
    for req in requirements {
        nodes.push(GraphNode {
            id: req.id.clone(),
            node_type: NodeType::Requirement,
            label: req.text.clone(),
        });
    }
    
    RequirementGraph { nodes, edges }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_build_graph() {
        let graph = build_requirement_graph(vec![]);
        assert_eq!(graph.nodes.len(), 0);
    }
}
