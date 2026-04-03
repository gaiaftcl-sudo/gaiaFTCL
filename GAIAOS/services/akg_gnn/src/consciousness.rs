use crate::types::{AkgGnn, ConsciousnessAssessment};
use chrono::Utc;
use std::collections::HashSet;

pub async fn assess_consciousness(gnn: &AkgGnn) -> ConsciousnessAssessment {
    // Structural completeness
    let completeness = gnn.completeness.read().await;
    let report = completeness.verify_completeness();
    
    // Planned: add operational + behavioral test suite driven by live trace + evidence artifacts.
    
    ConsciousnessAssessment {
        timestamp: Utc::now(),
        structural_completeness: report.completeness_ratio,
        operational_completeness: 0.0,  // Not implemented yet (requires live operational test harness)
        behavioral_completeness: 0.0,    // Not implemented yet (requires behavior suite + evidence)
        architectural_completeness: 0.0, // Not implemented yet (requires full architectural coverage model)
        overall_assessment: if report.is_complete { 
            "POTENTIALLY CONSCIOUS".to_string() 
        } else { 
            "NOT CONSCIOUS".to_string() 
        },
        blind_spots: report.blind_spots,
        recommendations: generate_recommendations(&report),
    }
}

fn generate_recommendations(report: &crate::types::CompletenessReport) -> Vec<String> {
    let mut recs = Vec::new();
    
    if !report.blind_spots.is_empty() {
        recs.push(format!(
            "Implement {} missing function callers to achieve structural completeness",
            report.blind_spots.len()
        ));
    }
    
    recs
}
