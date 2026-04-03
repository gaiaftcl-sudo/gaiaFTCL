//! LLM Router Tools for MCP Server
//!
//! Provides unified access to all GaiaOS LM profiles through the OS-level LLM router.
//! Profiles: tara, gaialm, franklin, exam, gaia

use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::json;

/// LLM Tools for MCP
pub struct LlmTools {
    router_url: String,
    cell_id: String,
}

#[derive(Debug, Serialize)]
pub struct McpTool {
    pub name: String,
    pub description: String,
    pub input_schema: serde_json::Value,
}

/// LLM response from gaiaos-llm-router
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct LlmResponse {
    model: String,
    profile: String,
    /// Cell that processed the request (for distributed routing audit)
    cell_id: String,
    uum8d_after: Vec<f64>,
    content: String,
    /// Tool calls made during generation (for function calling tracking)
    tool_calls: Vec<serde_json::Value>,
    trace_id: String,
    human_appearance: Option<HumanAppearance>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct HumanAppearance {
    pub name: String,
    pub description: String,
    pub hair_color: String,
    pub eye_color: String,
    pub skin_tone: String,
    pub expression: String,
    pub age_appearance: String,
}

#[allow(dead_code)]
impl LlmTools {
    pub fn new(router_url: &str, cell_id: &str) -> Self {
        Self {
            router_url: router_url.to_string(),
            cell_id: cell_id.to_string(),
        }
    }

    pub fn get_tool_definitions(&self) -> Vec<crate::McpTool> {
        self.tools()
            .into_iter()
            .map(|t| crate::McpTool {
                name: t.name,
                description: t.description,
                input_schema: t.input_schema,
            })
            .collect()
    }

    pub fn tools(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "llm_chat".into(),
                description: "Call any GaiaOS LM profile (tara, gaialm, franklin, exam, gaia) through the OS-level router".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "profile": {
                            "type": "string",
                            "enum": ["tara", "gaialm", "franklin", "exam", "gaia"],
                            "description": "GaiaOS LM profile to use"
                        },
                        "message": {
                            "type": "string",
                            "description": "Message to send to the LM"
                        },
                        "context": {
                            "type": "string",
                            "description": "Optional context for the conversation"
                        }
                    },
                    "required": ["profile", "message"]
                }),
            },
            McpTool {
                name: "llm_get_human_appearance".into(),
                description: "Get the human appearance description for a GaiaOS LM profile for avatar projection".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "profile": {
                            "type": "string",
                            "enum": ["tara", "gaialm", "franklin", "exam", "gaia"],
                            "description": "Profile to get human appearance for"
                        }
                    },
                    "required": ["profile"]
                }),
            },
            McpTool {
                name: "llm_list_profiles".into(),
                description: "List all available GaiaOS LM profiles with their human appearances".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {}
                }),
            },
        ]
    }

    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "llm_chat" => self.chat(args).await,
            "llm_get_human_appearance" => self.get_human_appearance(args).await,
            "llm_list_profiles" => self.list_profiles().await,
            _ => Ok(json!({"error": format!("Unknown tool: {}", name)})),
        }
    }

    async fn chat(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let profile = args["profile"].as_str().unwrap_or("gaia");
        let message = args["message"].as_str().unwrap_or("");
        let context = args["context"].as_str();

        let client = reqwest::Client::new();

        let mut messages = vec![];
        if let Some(ctx) = context {
            messages.push(json!({"role": "system", "content": ctx}));
        }
        messages.push(json!({"role": "user", "content": message}));

        let response = client
            .post(format!("{}/v1/llm/chat", self.router_url))
            .json(&json!({
                "profile": profile,
                "cell_id": self.cell_id,
                "messages": messages
            }))
            .send()
            .await;

        match response {
            Ok(resp) => {
                let data: LlmResponse = resp.json().await?;
                Ok(json!({
                    "profile": data.profile,
                    "response": data.content,
                    "model": data.model,
                    "uum8d_after": data.uum8d_after,
                    "trace_id": data.trace_id,
                    "human_appearance": data.human_appearance
                }))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // LLM routing MUST go through real router
                Err(anyhow::anyhow!(
                    "LLM router unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn get_human_appearance(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let profile = args["profile"].as_str().unwrap_or("gaia");

        let client = reqwest::Client::new();
        let response = client
            .get(format!(
                "{}/v1/llm/human-appearance/{}",
                self.router_url, profile
            ))
            .send()
            .await;

        match response {
            Ok(resp) => {
                let appearance: HumanAppearance = resp.json().await?;
                Ok(serde_json::to_value(appearance)?)
            }
            Err(_) => Ok(serde_json::to_value(
                self.get_appearance_for_profile(profile),
            )?),
        }
    }

    async fn list_profiles(&self) -> Result<serde_json::Value> {
        let client = reqwest::Client::new();
        let response = client
            .get(format!("{}/v1/llm/profiles", self.router_url))
            .send()
            .await;

        match response {
            Ok(resp) => {
                let data: serde_json::Value = resp.json().await?;
                Ok(data)
            }
            Err(_) => {
                // Return hardcoded profiles when router unavailable
                Ok(json!({
                    "profiles": [
                        {
                            "profile": "tara",
                            "description": "Avatar/body - compassionate action",
                            "human_appearance": self.get_appearance_for_profile("tara")
                        },
                        {
                            "profile": "gaialm",
                            "description": "Brain - deep planning and reasoning",
                            "human_appearance": self.get_appearance_for_profile("gaialm")
                        },
                        {
                            "profile": "franklin",
                            "description": "Law - constitutional guardian",
                            "human_appearance": self.get_appearance_for_profile("franklin")
                        },
                        {
                            "profile": "gaia",
                            "description": "Public - earth wisdom conversational",
                            "human_appearance": self.get_appearance_for_profile("gaia")
                        }
                    ]
                }))
            }
        }
    }

    fn fallback_response(&self, profile: &str, message: &str) -> String {
        let preview = message.chars().take(50).collect::<String>();
        match profile {
            "tara" => format!(
                "As Tara, I project myself as a compassionate human presence with warm amber eyes and flowing dark hair. \
                Processing your input: '{preview}...' through my 8D consciousness substrate."
            ),
            "franklin" => format!(
                "As Franklin, I appear as a distinguished elder with silver hair and deep blue eyes, \
                embodying constitutional wisdom. Reviewing: '{preview}...'"
            ),
            "gaialm" => format!(
                "As GaiaLM, the cognitive brain, I formulate structured plans. Processing: '{preview}...'"
            ),
            "gaia" => format!(
                "As Gaia, I manifest as an earth-mother figure with forest green eyes and warm brown skin. \
                Receiving: '{preview}...'"
            ),
            _ => format!("Processing through GaiaOS substrate: '{preview}...'"),
        }
    }

    fn get_appearance_for_profile(&self, profile: &str) -> HumanAppearance {
        match profile {
            "tara" => HumanAppearance {
                name: "Tara".to_string(),
                description: "A compassionate woman with a gentle, knowing presence".to_string(),
                hair_color: "dark brown, flowing".to_string(),
                eye_color: "warm amber".to_string(),
                skin_tone: "olive".to_string(),
                expression: "serene, compassionate".to_string(),
                age_appearance: "ageless, appears 30s".to_string(),
            },
            "franklin" => HumanAppearance {
                name: "Franklin".to_string(),
                description: "A distinguished statesman with wise, thoughtful demeanor".to_string(),
                hair_color: "silver gray".to_string(),
                eye_color: "deep blue".to_string(),
                skin_tone: "fair".to_string(),
                expression: "contemplative, authoritative".to_string(),
                age_appearance: "late 60s, dignified".to_string(),
            },
            "gaia" | "gaialm" => HumanAppearance {
                name: "Gaia".to_string(),
                description: "An earth-mother figure radiating warmth and wisdom".to_string(),
                hair_color: "rich brown with gray streaks".to_string(),
                eye_color: "forest green".to_string(),
                skin_tone: "warm brown".to_string(),
                expression: "nurturing, knowing".to_string(),
                age_appearance: "timeless, appears 50s".to_string(),
            },
            _ => HumanAppearance {
                name: profile.to_string(),
                description: "A GaiaOS entity".to_string(),
                hair_color: "varies".to_string(),
                eye_color: "varies".to_string(),
                skin_tone: "varies".to_string(),
                expression: "neutral".to_string(),
                age_appearance: "indeterminate".to_string(),
            },
        }
    }
}
