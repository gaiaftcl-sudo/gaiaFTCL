use anyhow::Result;
use crate::types::{Explanation, AkgGnn};
use uuid::Uuid;

pub async fn explain_decision(_gnn: &AkgGnn, decision_id: Uuid) -> Result<Explanation> {
    // Planned: implement decision explanation via GNN reasoning
    Ok(Explanation {
        decision_id,
        reasoning_path: vec![],
        natural_language: "Not yet implemented".to_string(),
        confidence: 0.0,
    })
}
