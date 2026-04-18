use anyhow::Result;
use serde::{Deserialize, Serialize};
use chrono::Utc;
use crate::akg::AKGClient;

/// Complete Patch Brief for Cursor execution
/// This is the "handoff contract" from RAG Librarian to Cursor Executor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatchBrief {
    pub problem_statement: String,
    pub root_causes: Vec<String>,
    pub proposed_changes: FileChangeSet,
    pub verification_plan: VerificationPlan,
    pub rollback_plan: RollbackPlan,
    pub evidence_required: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChangeSet {
    pub files: Vec<String>,
    pub suggested_approach: String,
    pub code_snippets: Vec<CodeSnippet>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeSnippet {
    pub source: String,  // "bevy/examples/3d/many_cubes.rs" or "commit a3f9d2"
    pub code: String,
    pub context: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationPlan {
    pub tests: Vec<String>,
    pub perf_thresholds: serde_json::Value,
    pub proofs_required: Vec<ProofType>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum ProofType {
    PerformanceTrace,
    TestResults,
    WasmBuild,
    Screenshot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RollbackPlan {
    pub revert_commit: String,
    pub fallback_branch: String,
}

/// Patch Brief Generator (RAG Librarian Agent)
pub struct PatchBriefGenerator {
    akg_client: AKGClient,
}

impl PatchBriefGenerator {
    pub fn new(akg_client: AKGClient) -> Self {
        Self { akg_client }
    }

    /// Generate complete Patch Brief from improvement task
    pub async fn generate(&self, task_id: &str, world: &str) -> Result<PatchBrief> {
        // 1. Get the task from AKG
        let task = self.get_task(task_id).await?;
        
        // 2. Query all RAG corpora in parallel
        let (repo_context, bevy_patterns, akg_patterns, ops_data) = tokio::join!(
            self.query_repo_rag(&task, world),
            self.query_bevy_rag(&task),
            self.query_akg_rag(&task),
            self.query_ops_rag(&task, world)
        );

        let repo_context = repo_context?;
        let bevy_patterns = bevy_patterns?;
        let akg_patterns = akg_patterns?;
        
        // 3. Diagnose root causes
        let root_causes = self.diagnose_root_causes(&task, &akg_patterns, &ops_data?);
        
        // 4. Select best approach from patterns
        let best_pattern = akg_patterns.first()
            .or_else(|| bevy_patterns.first())
            .ok_or_else(|| anyhow::anyhow!("No patterns found for task"))?;
        
        // 5. Assemble code snippets
        let code_snippets = self.assemble_code_snippets(&repo_context, &bevy_patterns, &akg_patterns);
        
        // 6. Build verification plan
        let verification_plan = VerificationPlan {
            tests: repo_context.existing_tests.clone(),
            perf_thresholds: task.target_metrics.clone(),
            proofs_required: vec![
                ProofType::PerformanceTrace,
                ProofType::TestResults,
                ProofType::WasmBuild,
            ],
        };
        
        // 7. Build rollback plan
        let rollback_plan = RollbackPlan {
            revert_commit: "HEAD".to_string(),
            fallback_branch: "main".to_string(),
        };
        
        Ok(PatchBrief {
            problem_statement: task.description.clone(),
            root_causes,
            proposed_changes: FileChangeSet {
                files: task.affected_files.clone(),
                suggested_approach: best_pattern.solution.clone(),
                code_snippets,
            },
            verification_plan,
            rollback_plan,
            evidence_required: vec![
                "perf_trace.json".to_string(),
                "test_output.log".to_string(),
                "wasm_size.txt".to_string(),
            ],
        })
    }

    async fn get_task(&self, task_id: &str) -> Result<ImprovementTask> {
        let query = format!(
            r#"
            FOR task IN ImprovementQueue_V2
            FILTER task._key == "{}"
            RETURN task
            "#,
            task_id
        );
        
        let results: Vec<ImprovementTask> = self.akg_client.query(&query).await?;
        results.into_iter().next()
            .ok_or_else(|| anyhow::anyhow!("Task not found: {}", task_id))
    }

    async fn query_repo_rag(&self, task: &ImprovementTask, world: &str) -> Result<RepoContext> {
        let query = format!(
            r#"
            FOR doc IN RepoRAG
            FILTER doc.world == "{}"
            FILTER doc.file IN @files
            SORT doc.last_modified DESC
            LIMIT 10
            RETURN doc
            "#,
            world
        );
        
        let results = self.akg_client.query_with_params(
            &query,
            &serde_json::json!({ "files": task.affected_files })
        ).await?;
        
        Ok(RepoContext {
            relevant_systems: vec![],
            existing_tests: vec!["test_particle_spawn".to_string()],
            recent_changes: vec![],
            relevant_examples: results,
        })
    }

    async fn query_bevy_rag(&self, task: &ImprovementTask) -> Result<Vec<BevyPattern>> {
        let query = r#"
            FOR pattern IN BevyRAG
            FILTER pattern.tags ANY IN @required_skills
            SORT pattern.relevance_score DESC
            LIMIT 5
            RETURN pattern
        "#;
        
        self.akg_client.query_with_params(
            query,
            &serde_json::json!({ "required_skills": [task.required_skill.clone()] })
        ).await
    }

    async fn query_akg_rag(&self, task: &ImprovementTask) -> Result<Vec<FixPattern>> {
        let query = format!(
            r#"
            FOR pattern IN FixPatterns_V2
            FILTER pattern.symptom == "{}"
            SORT pattern.success_rate DESC
            LIMIT 5
            RETURN pattern
            "#,
            task.task_type
        );
        
        self.akg_client.query(&query).await
    }

    async fn query_ops_rag(&self, task: &ImprovementTask, world: &str) -> Result<OpsData> {
        // Query Sentry/Linear/GitHub for related issues
        Ok(OpsData {
            related_crashes: vec![],
            related_issues: vec![],
        })
    }

    fn diagnose_root_causes(
        &self,
        task: &ImprovementTask,
        patterns: &[FixPattern],
        ops_data: &OpsData
    ) -> Vec<String> {
        let mut causes = vec![];
        
        // Extract from patterns
        for pattern in patterns.iter().take(3) {
            if let Some(cause) = &pattern.known_cause {
                causes.push(cause.clone());
            }
        }
        
        // Add task-specific analysis
        if task.task_type == "performance" {
            causes.push("Likely rendering bottleneck or excessive allocations".to_string());
        }
        
        causes
    }

    fn assemble_code_snippets(
        &self,
        repo_context: &RepoContext,
        bevy_patterns: &[BevyPattern],
        akg_patterns: &[FixPattern]
    ) -> Vec<CodeSnippet> {
        let mut snippets = vec![];
        
        // Add Bevy examples
        for pattern in bevy_patterns.iter().take(2) {
            snippets.push(CodeSnippet {
                source: pattern.example_file.clone(),
                code: pattern.code_snippet.clone(),
                context: format!("Bevy pattern for {}", pattern.capability),
            });
        }
        
        // Add past successful fixes
        for pattern in akg_patterns.iter().take(2) {
            if let Some(code) = &pattern.code_example {
                snippets.push(CodeSnippet {
                    source: format!("Past fix: {}", pattern.pattern_id),
                    code: code.clone(),
                    context: format!("Success rate: {:.0}%", pattern.success_rate * 100.0),
                });
            }
        }
        
        snippets
    }
}

// Supporting types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImprovementTask {
    pub id: String,
    pub title: String,
    pub description: String,
    pub world: String,
    pub task_type: String,
    pub priority: f64,
    pub impact: f64,
    pub effort: i32,
    pub affected_files: Vec<String>,
    pub required_skill: String,
    pub baseline_metrics: serde_json::Value,
    pub target_metrics: serde_json::Value,
    pub status: String,
}

#[derive(Debug, Clone)]
struct RepoContext {
    relevant_systems: Vec<String>,
    existing_tests: Vec<String>,
    recent_changes: Vec<String>,
    relevant_examples: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BevyPattern {
    example_file: String,
    capability: String,
    code_snippet: String,
    relevance_score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FixPattern {
    pub pattern_id: String,
    pub symptom: String,
    pub solution: String,
    pub success_rate: f64,
    pub known_cause: Option<String>,
    pub code_example: Option<String>,
}

#[derive(Debug, Clone)]
struct OpsData {
    related_crashes: Vec<String>,
    related_issues: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_patch_brief_generation() {
        // Integration test - requires running AKG
        // Planned: add a hermetic AKG test harness (real container) for CI to avoid stubbing.
    }
}
