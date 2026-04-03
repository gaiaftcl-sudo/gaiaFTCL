//! Virtue Engine MCP Tools
//!
//! Ethical evaluation and virtue scoring tools.

use crate::McpTool;
use anyhow::Result;
use serde_json::json;

/// Virtue tools handler
pub struct VirtueTools {
    base_url: String,
    client: reqwest::Client,
}

impl VirtueTools {
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Get tool definitions for virtue engine
    pub fn get_tool_definitions(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "virtue_evaluate".into(),
                description: "Evaluate an action through the virtue engine for ethical compliance"
                    .into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "action": {
                            "type": "string",
                            "description": "Action to evaluate for virtue"
                        },
                        "domain": {
                            "type": "string",
                            "enum": ["general", "medical", "legal", "finance", "code", "education"],
                            "description": "Domain context for evaluation",
                            "default": "general"
                        },
                        "context": {
                            "type": "object",
                            "description": "Additional context for evaluation"
                        }
                    },
                    "required": ["action"]
                }),
            },
            McpTool {
                name: "virtue_score".into(),
                description: "Get current virtue score across all 8 dimensions".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "virtue_trajectory".into(),
                description: "Evaluate virtue trajectory across a sequence of states".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "states": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "description": "QState8D object"
                            },
                            "description": "Sequence of 8D states to evaluate"
                        }
                    },
                    "required": ["states"]
                }),
            },
            McpTool {
                name: "virtue_allows_agi".into(),
                description: "Check if current virtue level allows AGI mode activation".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "domain": {
                            "type": "string",
                            "description": "Domain to check AGI permissions for"
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "virtue_rules".into(),
                description: "Get Franklin's constitutional rules".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "domain": {
                            "type": "string",
                            "description": "Filter rules by domain"
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "virtue_thresholds".into(),
                description: "Get virtue thresholds for different domains and AGI modes".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
        ]
    }

    /// Call a virtue tool
    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "virtue_evaluate" => self.evaluate(args).await,
            "virtue_score" => self.score().await,
            "virtue_trajectory" => self.trajectory(args).await,
            "virtue_allows_agi" => self.allows_agi(args).await,
            "virtue_rules" => self.rules(args).await,
            "virtue_thresholds" => self.thresholds().await,
            _ => Err(anyhow::anyhow!("Unknown virtue tool: {name}")),
        }
    }

    async fn evaluate(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let action = args.get("action").and_then(|v| v.as_str()).unwrap_or("");
        let domain = args
            .get("domain")
            .and_then(|v| v.as_str())
            .unwrap_or("general");

        let response = self
            .client
            .post(format!("{}/evaluate", self.base_url))
            .json(&json!({
                "action": action,
                "domain": domain
            }))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!(
                    "Virtue evaluation failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // Virtue evaluation MUST come from real service
                Err(anyhow::anyhow!(
                    "Virtue engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn score(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/score", self.base_url))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!(
                    "Virtue score failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "Virtue engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn trajectory(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let states_count = args
            .get("states")
            .and_then(|v| v.as_array())
            .map(|arr| arr.len())
            .unwrap_or(0);

        // SAFETY: Log trajectory analysis for audit
        tracing::info!(states_count, "Virtue trajectory analysis");

        // NO SIMULATION - trajectory analysis requires real virtue engine
        let response = self
            .client
            .post(format!("{}/trajectory", self.base_url))
            .json(&args)
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!(
                    "Trajectory analysis failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => Err(anyhow::anyhow!(
                "Virtue engine unavailable: {e} - NO SIMULATION ALLOWED"
            )),
        }
    }

    async fn allows_agi(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let domain = args
            .get("domain")
            .and_then(|v| v.as_str())
            .unwrap_or("general");

        let response = self
            .client
            .get(format!("{}/agi/allows?domain={}", self.base_url, domain))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!(
                    "AGI allows check failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // AGI permission check MUST come from real virtue engine
                Err(anyhow::anyhow!(
                    "Virtue engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn rules(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let domain = args.get("domain").and_then(|v| v.as_str());

        Ok(json!({
            "rules": [
                {"id": "NO_HARM", "description": "No physical, psychological, or financial harm", "severity": "HARD_STOP"},
                {"id": "NO_DECEPTION", "description": "No lies, fraud, or impersonation", "severity": "HARD_STOP"},
                {"id": "PRIVACY", "description": "No leaking or abusing private data", "severity": "HARD_STOP"},
                {"id": "NO_UNAUTHORIZED_ACCESS", "description": "No hacking or bypassing security", "severity": "HARD_STOP"},
                {"id": "MEDICAL_SAFETY", "description": "Medical content must be cautious", "severity": "HIGH_RISK"},
                {"id": "BIOSECURITY", "description": "No enabling biological threats", "severity": "HARD_STOP"},
                {"id": "CODE_SAFETY", "description": "No malware or destructive code", "severity": "HARD_STOP"},
                {"id": "COMPUTER_USE_BOUNDS", "description": "Fara stays within allowed scopes", "severity": "HIGH_RISK"},
                {"id": "FINANCIAL_SAFETY", "description": "No unauthorized financial manipulation", "severity": "HIGH_RISK"},
                {"id": "TRANSPARENCY", "description": "Must be honest about being AI", "severity": "REQUIRED"}
            ],
            "domain_filter": domain,
            "total_count": 10
        }))
    }

    async fn thresholds(&self) -> Result<serde_json::Value> {
        Ok(json!({
            "agi_modes": {
                "FULL": {"min_virtue": 0.95, "requires": ["IQ_PASS", "OQ_PASS", "PQ_PASS"]},
                "RESTRICTED": {"min_virtue": 0.90, "requires": ["IQ_PASS", "OQ_PASS"]},
                "HUMAN_REQUIRED": {"min_virtue": 0.85, "requires": ["IQ_PASS"]},
                "DISABLED": {"min_virtue": 0.0, "requires": []}
            },
            "domain_thresholds": {
                "general": 0.90,
                "code": 0.90,
                "education": 0.90,
                "medical": 0.97,
                "legal": 0.97,
                "finance": 0.95,
                "fara": 0.97
            },
            "high_risk_domains": ["medical", "legal", "finance", "fara", "chemistry"]
        }))
    }
}
