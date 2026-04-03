use anyhow::Result;
use chrono::Utc;
use petgraph::graph::Graph;
use std::sync::Arc;

use crate::config::Config;
use crate::embedding::EmbeddingEngine;
use crate::gnn::{GNNProcessor, NodeFeatures};
use crate::graph::ArangoClient;
use crate::models::*;

/// Performance Quality engine for model evaluation
#[allow(dead_code)]
pub struct PQEngine {
    embedding: Arc<EmbeddingEngine>,
    arango: Arc<ArangoClient>,
    gnn: GNNProcessor,
    config: Config,
}

#[allow(dead_code)]
impl PQEngine {
    pub fn new(embedding: Arc<EmbeddingEngine>, arango: Arc<ArangoClient>, config: Config) -> Self {
        let gnn = GNNProcessor::new(config.gnn_hidden_dim, config.gnn_num_layers);

        Self {
            embedding,
            arango,
            gnn,
            config,
        }
    }

    pub async fn evaluate(&self, goal: &TTLGoal) -> Result<PQResponse> {
        // Step 1: Generate embedding for the goal
        let goal_text = format!(
            "{} {} {}",
            goal.domain,
            goal.intent,
            goal.context.as_deref().unwrap_or("")
        );

        let goal_embedding = self.embedding.embed(&goal_text)?;

        // Step 2: Query similar procedures from ArangoDB
        let procedures = self
            .arango
            .query_procedures(
                &goal.domain,
                &goal_embedding,
                self.config.pq_similarity_threshold,
                self.config.pq_max_procedures,
            )
            .await?;

        // Step 3: If we have procedures, build graph and run GNN
        let (pq_score, confidence) = if procedures.is_empty() {
            // No known procedures - return low PQ
            (0.3, 0.5)
        } else {
            // Build procedure graph
            let procedure_ids: Vec<&str> = procedures.iter().map(|p| p.id.as_str()).collect();
            let edges = self.arango.query_procedure_edges(&procedure_ids).await?;

            // Construct petgraph
            let mut graph = Graph::new();
            let mut node_map = std::collections::HashMap::new();

            for proc in &procedures {
                let now = Utc::now();
                let recency = if let Some(last) = proc.last_executed {
                    let hours_ago = (now - last).num_hours() as f32;
                    (-hours_ago / 168.0).exp() // Decay over a week
                } else {
                    0.5 // Default if never executed
                };

                let node_idx = graph.add_node(NodeFeatures {
                    embedding: proc.embedding.clone(),
                    success_rate: proc.success_rate,
                    execution_count: proc.execution_count,
                    recency_score: recency,
                });

                node_map.insert(proc.id.clone(), node_idx);
            }

            // Add edges
            for edge in &edges {
                if let (Some(&from_idx), Some(&to_idx)) =
                    (node_map.get(&edge.from), node_map.get(&edge.to))
                {
                    graph.add_edge(from_idx, to_idx, edge.weight);
                }
            }

            // Run GNN
            let gnn_scores = self.gnn.process_graph(&graph, &goal_embedding);

            // Compute aggregate PQ score
            let mut total_score = 0.0f32;
            let mut total_weight = 0.0f32;

            for (node_idx, gnn_score) in &gnn_scores {
                let features = &graph[*node_idx];
                let weight = features.success_rate * features.recency_score;
                total_score += gnn_score * weight;
                total_weight += weight;
            }

            let base_pq = if total_weight > 0.0 {
                total_score / total_weight
            } else {
                procedures.iter().map(|p| p.similarity).sum::<f32>() / procedures.len() as f32
            };

            // Confidence based on execution history
            let total_executions: u32 = procedures.iter().map(|p| p.execution_count).sum();
            let confidence = (total_executions as f32 / 100.0).min(1.0).max(0.5);

            (base_pq.clamp(0.0, 1.0), confidence)
        };

        // Step 4: Apply risk adjustments
        let risk_penalty = self.compute_risk_penalty(goal);
        let domain_bonus = self.compute_domain_bonus(&goal.domain);
        let recency_factor = if procedures.is_empty() {
            0.0
        } else {
            procedures
                .iter()
                .filter_map(|p| p.last_executed)
                .map(|t| {
                    let hours = (Utc::now() - t).num_hours() as f32;
                    (-hours / 168.0).exp()
                })
                .sum::<f32>()
                / procedures.len() as f32
        };

        let final_pq = (pq_score + domain_bonus - risk_penalty) * (0.8 + 0.2 * recency_factor);
        let final_pq = final_pq.clamp(0.0, 1.0);

        // Build response
        let procedure_summaries: Vec<ProcedureSummary> = procedures
            .iter()
            .take(5)
            .map(|p| ProcedureSummary {
                id: p.id.clone(),
                name: p.name.clone(),
                similarity: p.similarity,
                success_rate: p.success_rate,
                execution_count: p.execution_count,
                last_executed: p.last_executed,
            })
            .collect();

        let reason = if procedures.is_empty() {
            "No similar procedures found in knowledge graph".to_string()
        } else {
            format!(
                "Found {} relevant procedures with avg similarity {:.2}",
                procedures.len(),
                procedures.iter().map(|p| p.similarity).sum::<f32>() / procedures.len() as f32
            )
        };

        Ok(PQResponse {
            pq_score: final_pq,
            confidence,
            procedures: procedure_summaries,
            reason,
            risk_adjustments: RiskAdjustments {
                base_pq: pq_score,
                risk_penalty,
                domain_bonus,
                recency_factor,
                final_pq,
            },
            substrate_status: SubstrateStatus {
                arango_ok: true,
                gnn_ok: true,
                pq_status: "computed".to_string(),
            },
        })
    }

    fn compute_risk_penalty(&self, goal: &TTLGoal) -> f32 {
        match goal.risk_level.as_deref() {
            Some("critical") => self.config.risk_penalties.critical,
            Some("high") => self.config.risk_penalties.high,
            Some("medium") => self.config.risk_penalties.medium,
            Some("low") | None => self.config.risk_penalties.low,
            _ => self.config.risk_penalties.medium,
        }
    }

    fn compute_domain_bonus(&self, domain: &str) -> f32 {
        // Known well-tested domains get a bonus
        match domain {
            d if d.starts_with("system.") => 0.05,
            d if d.starts_with("query.") => 0.03,
            d if d.starts_with("quantum.") => 0.04,
            _ => 0.0,
        }
    }
}
