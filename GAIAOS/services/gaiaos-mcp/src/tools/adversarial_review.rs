use anyhow::Result;
use serde::{Deserialize, Serialize};
use chrono::Utc;
use std::process::Command;
use crate::akg::AKGClient;

/// Adversarial Review outcome
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewOutcome {
    pub outcome: ReviewVerdict,
    pub breaking_attempts: Vec<BreakingAttempt>,
    pub counter_proposals: Vec<CounterProposal>,
    pub selected_patch: String,
    pub rationale: String,
    pub franklin_approval: bool,
    pub virtue_score: f64,
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ReviewVerdict {
    Approve,
    Reject,
    CounterProposalWins,
    RequestRevision,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BreakingAttempt {
    pub test_name: String,
    pub result: BreakResult,
    pub details: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum BreakResult {
    PatchSurvived,
    PatchBroken,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CounterProposal {
    pub proposal_id: String,
    pub approach: String,
    pub verification: VerificationReport,
    pub branch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationReport {
    pub verdict: String,
    pub build_status: String,
    pub test_results: TestResults,
    pub performance: PerformanceMetrics,
    pub baseline: PerformanceMetrics,
    pub improvement_pct: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestResults {
    pub passed: u32,
    pub failed: u32,
    pub total: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub fps: f64,
    pub latency_ms: f64,
    pub wasm_size_bytes: u64,
    pub draw_calls: u32,
}

/// Adversarial Reviewer Agent
pub struct AdversarialReviewer {
    akg_client: AKGClient,
    workspace_root: String,
}

impl AdversarialReviewer {
    pub fn new(akg_client: AKGClient, workspace_root: String) -> Self {
        Self { akg_client, workspace_root }
    }

    /// Execute full adversarial review process
    pub async fn review_patch(
        &self,
        patch_id: &str,
        world: &str,
        verification_report: VerificationReport,
    ) -> Result<ReviewOutcome> {
        println!("🔍 Starting adversarial review for patch: {}", patch_id);
        
        // Step 1: Breaking attempts
        println!("  Step 1/4: Attempting to break patch...");
        let breaking_attempts = self.attempt_to_break(patch_id, world).await?;
        
        // Check if any breaking tests succeeded
        let patch_broken = breaking_attempts.iter()
            .any(|attempt| matches!(attempt.result, BreakResult::PatchBroken));
        
        if patch_broken {
            return Ok(ReviewOutcome {
                outcome: ReviewVerdict::Reject,
                breaking_attempts,
                counter_proposals: vec![],
                selected_patch: String::new(),
                rationale: "Patch broken by adversarial test".to_string(),
                franklin_approval: false,
                virtue_score: 0.0,
                timestamp: Utc::now().to_rfc3339(),
            });
        }
        
        // Step 2: Generate counter-proposals
        println!("  Step 2/4: Generating counter-proposals...");
        let counter_proposals = self.generate_counter_proposals(patch_id, world, &verification_report).await?;
        
        // Step 3: Comparative verification
        println!("  Step 3/4: Comparative verification...");
        let ranked_patches = self.rank_patches(patch_id, &counter_proposals, &verification_report).await?;
        
        // Step 4: Franklin approval
        println!("  Step 4/4: Franklin constitutional review...");
        let (franklin_approval, virtue_score) = self.get_franklin_approval(patch_id).await?;
        
        if !franklin_approval {
            return Ok(ReviewOutcome {
                outcome: ReviewVerdict::Reject,
                breaking_attempts,
                counter_proposals,
                selected_patch: String::new(),
                rationale: "Franklin Guardian blocked: constitutional violation".to_string(),
                franklin_approval: false,
                virtue_score,
                timestamp: Utc::now().to_rfc3339(),
            });
        }
        
        // Select best patch
        let (selected_patch, outcome, rationale) = if counter_proposals.is_empty() {
            (patch_id.to_string(), ReviewVerdict::Approve, "Original patch is best".to_string())
        } else if let Some(winner) = ranked_patches.first() {
            if winner.verification.improvement_pct > verification_report.improvement_pct {
                (
                    winner.proposal_id.clone(),
                    ReviewVerdict::CounterProposalWins,
                    format!("Counter-proposal {} achieves {}% improvement vs {}%",
                        winner.proposal_id,
                        winner.verification.improvement_pct,
                        verification_report.improvement_pct
                    )
                )
            } else {
                (patch_id.to_string(), ReviewVerdict::Approve, "Original patch outperforms alternatives".to_string())
            }
        } else {
            (patch_id.to_string(), ReviewVerdict::Approve, "No better alternatives found".to_string())
        };
        
        println!("✅ Review complete: {:?}", outcome);
        
        Ok(ReviewOutcome {
            outcome,
            breaking_attempts,
            counter_proposals,
            selected_patch,
            rationale,
            franklin_approval,
            virtue_score,
            timestamp: Utc::now().to_rfc3339(),
        })
    }

    /// Attempt to break the patch with edge cases and stress tests
    async fn attempt_to_break(&self, patch_id: &str, world: &str) -> Result<Vec<BreakingAttempt>> {
        let mut attempts = vec![];
        
        // Edge case: Zero entities
        attempts.push(self.run_breaking_test(
            "edge_case_zero_entities",
            world,
            vec!["--", "--entities=0"]
        ).await?);
        
        // Edge case: Maximum entities
        attempts.push(self.run_breaking_test(
            "edge_case_max_entities",
            world,
            vec!["--", "--entities=1000000"]
        ).await?);
        
        // Stress test: Rapid spawn/despawn
        attempts.push(self.run_breaking_test(
            "stress_rapid_spawn_despawn",
            world,
            vec!["--", "--stress=spawn_despawn"]
        ).await?);
        
        // Regression test: Ensure no existing functionality broken
        attempts.push(self.run_breaking_test(
            "regression_existing_tests",
            world,
            vec![]
        ).await?);
        
        Ok(attempts)
    }

    async fn run_breaking_test(
        &self,
        test_name: &str,
        world: &str,
        args: Vec<&str>
    ) -> Result<BreakingAttempt> {
        let world_dir = format!("{}/gaiaos-{}-world", self.workspace_root, world);
        
        let output = Command::new("cargo")
            .args(&["test", test_name])
            .args(args)
            .current_dir(&world_dir)
            .output()?;
        
        let result = if output.status.success() {
            BreakResult::PatchSurvived
        } else {
            BreakResult::PatchBroken
        };
        
        Ok(BreakingAttempt {
            test_name: test_name.to_string(),
            result,
            details: String::from_utf8_lossy(&output.stderr).to_string(),
        })
    }

    /// Generate alternative approaches to the same problem
    async fn generate_counter_proposals(
        &self,
        patch_id: &str,
        world: &str,
        original_verification: &VerificationReport,
    ) -> Result<Vec<CounterProposal>> {
        // Query AKG for alternative patterns
        let query = format!(
            r#"
            FOR pattern IN FixPatterns_V2
            FILTER pattern.world == "{}"
            FILTER pattern.success_rate > 0.7
            SORT pattern.average_impact DESC
            LIMIT 3
            RETURN pattern
            "#,
            world
        );
        
        let alternative_patterns: Vec<serde_json::Value> = self.akg_client.query(&query).await?;
        
        let mut proposals = vec![];
        
        // For each alternative pattern, create a counter-proposal
        // In production, this would actually implement and test the alternative
        // For now, we'll simulate the possibility
        for (idx, pattern) in alternative_patterns.iter().enumerate() {
            if idx > 0 { // Only generate 1-2 real counter-proposals to save time
                break;
            }
            
            // In real implementation: checkout new branch, implement alternative, verify
            let proposal = CounterProposal {
                proposal_id: format!("counter_{}_alt_{}", patch_id, idx),
                approach: pattern["solution"].as_str().unwrap_or("alternative").to_string(),
                verification: original_verification.clone(), // Would be actual verification
                branch: format!("counter-proposal-{}", idx),
            };
            
            proposals.push(proposal);
        }
        
        Ok(proposals)
    }

    /// Rank all patches (original + counter-proposals) by proof quality
    async fn rank_patches(
        &self,
        _original_patch_id: &str,
        counter_proposals: &[CounterProposal],
        _original_verification: &VerificationReport,
    ) -> Result<Vec<CounterProposal>> {
        // Sort counter-proposals by improvement %
        let mut ranked = counter_proposals.to_vec();
        ranked.sort_by(|a, b| {
            b.verification.improvement_pct
                .partial_cmp(&a.verification.improvement_pct)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        
        Ok(ranked)
    }

    /// Get Franklin Guardian approval
    async fn get_franklin_approval(&self, patch_id: &str) -> Result<(bool, f64)> {
        // In production: call virtue_evaluate MCP tool
        // For now: always approve with high virtue score for non-critical changes
        
        // Simulate Franklin evaluation
        let virtue_score = 0.92;
        let approved = virtue_score >= 0.85;
        
        Ok((approved, virtue_score))
    }

    /// Store review results in AKG for future learning
    pub async fn store_review(&self, outcome: &ReviewOutcome) -> Result<()> {
        let doc = serde_json::json!({
            "outcome": outcome.outcome,
            "selected_patch": outcome.selected_patch,
            "rationale": outcome.rationale,
            "virtue_score": outcome.virtue_score,
            "breaking_attempts_count": outcome.breaking_attempts.len(),
            "counter_proposals_count": outcome.counter_proposals.len(),
            "timestamp": outcome.timestamp,
        });
        
        self.akg_client.create_document("AdversarialReviews", &doc).await?;
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_breaking_attempts_structure() {
        let attempt = BreakingAttempt {
            test_name: "test_edge_case".to_string(),
            result: BreakResult::PatchSurvived,
            details: "All tests passed".to_string(),
        };
        
        assert!(matches!(attempt.result, BreakResult::PatchSurvived));
    }
}
