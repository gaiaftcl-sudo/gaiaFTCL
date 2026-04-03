//! Cell Management MCP Tools
//!
//! Deployment, monitoring, and administration tools.

use crate::McpTool;
use anyhow::Result;
use serde_json::json;
use std::process::Command;

/// Management tools handler
pub struct ManagementTools {
    cell_id: String,
}

impl ManagementTools {
    pub fn new(cell_id: &str) -> Self {
        Self {
            cell_id: cell_id.to_string(),
        }
    }

    /// Get tool definitions for management
    pub fn get_tool_definitions(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "cell_health".into(),
                description: "Health check all GaiaOS services on this cell".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "cell_logs".into(),
                description: "Get logs from a specific service".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "service": {
                            "type": "string",
                            "description": "Service name (e.g., 'virtue-engine', 'uum8d-brain')"
                        },
                        "lines": {
                            "type": "integer",
                            "description": "Number of log lines to retrieve",
                            "default": 50
                        },
                        "follow": {
                            "type": "boolean",
                            "description": "Follow log output (streaming)",
                            "default": false
                        }
                    },
                    "required": ["service"]
                }),
            },
            McpTool {
                name: "cell_restart".into(),
                description: "Restart a specific service".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "service": {
                            "type": "string",
                            "description": "Service name to restart"
                        }
                    },
                    "required": ["service"]
                }),
            },
            McpTool {
                name: "cell_deploy".into(),
                description: "Deploy or update services using docker-compose".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "compose_file": {
                            "type": "string",
                            "description": "Path to docker-compose file",
                            "default": "/opt/gaiaos/docker-compose.yml"
                        },
                        "services": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Specific services to deploy (empty = all)"
                        },
                        "pull": {
                            "type": "boolean",
                            "description": "Pull latest images before deploying",
                            "default": true
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "cell_status".into(),
                description: "Get full status of this GaiaOS cell".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "cell_containers".into(),
                description: "List all running containers on this cell".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "all": {
                            "type": "boolean",
                            "description": "Include stopped containers",
                            "default": false
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "cell_resources".into(),
                description: "Get cell resource usage (CPU, memory, disk)".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "cell_exec".into(),
                description: "Execute a command on the cell (admin only)".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "description": "Command to execute"
                        },
                        "working_dir": {
                            "type": "string",
                            "description": "Working directory"
                        }
                    },
                    "required": ["command"]
                }),
            },
        ]
    }

    /// Call a management tool
    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "cell_health" => self.health().await,
            "cell_logs" => self.logs(args).await,
            "cell_restart" => self.restart(args).await,
            "cell_deploy" => self.deploy(args).await,
            "cell_status" => self.status().await,
            "cell_containers" => self.containers(args).await,
            "cell_resources" => self.resources().await,
            "cell_exec" => self.exec(args).await,
            _ => Err(anyhow::anyhow!("Unknown management tool: {name}")),
        }
    }

    async fn health(&self) -> Result<serde_json::Value> {
        let services = vec![
            ("nats", "4222"),
            ("arangodb", "8529"),
            ("ollama", "11434"),
            ("gaia1-chip", "8001"),
            ("virtue-engine", "8810"),
            ("franklin-guardian", "8803"),
            ("gaiaos-agent", "8804"),
            ("world-engine", "8060"),
            ("uum8d-brain", "8050"),
            ("gaiaos-24h-cycle", "8060"),
            ("mcp-server", "9000"),
        ];

        let mut health_results = Vec::new();
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(2))
            .build()
            .unwrap_or_default();

        for (name, port) in &services {
            let url = format!("http://127.0.0.1:{port}/health");
            let status = match client.get(&url).send().await {
                Ok(resp) if resp.status().is_success() => "healthy",
                Ok(_) => "unhealthy",
                Err(_) => "unreachable",
            };
            health_results.push(json!({
                "service": name,
                "port": port,
                "status": status
            }));
        }

        let healthy_count = health_results.iter()
            .filter(|r| r.get("status").and_then(|s| s.as_str()) == Some("healthy"))
            .count();

        Ok(json!({
            "cell_id": self.cell_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "overall": if healthy_count >= services.len() / 2 { "healthy" } else { "degraded" },
            "healthy_count": healthy_count,
            "total_count": services.len(),
            "services": health_results
        }))
    }

    async fn logs(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let service = args.get("service")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let lines = args.get("lines")
            .and_then(|v| v.as_i64())
            .unwrap_or(50);

        let output = Command::new("docker")
            .args(["logs", "--tail", &lines.to_string(), service])
            .output();

        match output {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                let stderr = String::from_utf8_lossy(&out.stderr);
                
                Ok(json!({
                    "service": service,
                    "lines": lines,
                    "logs": if stdout.is_empty() { stderr.to_string() } else { stdout.to_string() },
                    "success": out.status.success()
                }))
            }
            Err(e) => {
                Ok(json!({
                    "service": service,
                    "error": format!("Failed to get logs: {}", e),
                    "success": false
                }))
            }
        }
    }

    async fn restart(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let service = args.get("service")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let output = Command::new("docker")
            .args(["restart", service])
            .output();

        match output {
            Ok(out) => {
                Ok(json!({
                    "service": service,
                    "action": "restart",
                    "success": out.status.success(),
                    "message": if out.status.success() {
                        format!("Service {service} restarted successfully")
                    } else {
                        String::from_utf8_lossy(&out.stderr).to_string()
                    }
                }))
            }
            Err(e) => {
                Ok(json!({
                    "service": service,
                    "action": "restart",
                    "success": false,
                    "error": format!("Failed to restart: {}", e)
                }))
            }
        }
    }

    async fn deploy(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let compose_file = args.get("compose_file")
            .and_then(|v| v.as_str())
            .unwrap_or("/opt/gaiaos/docker-compose.yml");
        let pull = args.get("pull")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let mut cmd_args = vec!["-f", compose_file];
        
        if pull {
            // First pull
            let _ = Command::new("docker")
                .args(["-f", compose_file, "compose", "pull"])
                .output();
        }

        cmd_args.extend(["compose", "up", "-d"]);

        let output = Command::new("docker")
            .args(&cmd_args)
            .output();

        match output {
            Ok(out) => {
                Ok(json!({
                    "compose_file": compose_file,
                    "action": "deploy",
                    "pulled": pull,
                    "success": out.status.success(),
                    "output": String::from_utf8_lossy(&out.stdout).to_string(),
                    "error": String::from_utf8_lossy(&out.stderr).to_string()
                }))
            }
            Err(e) => {
                Ok(json!({
                    "compose_file": compose_file,
                    "action": "deploy",
                    "success": false,
                    "error": format!("Deploy failed: {}", e)
                }))
            }
        }
    }

    async fn status(&self) -> Result<serde_json::Value> {
        let health = self.health().await?;
        let containers = self.containers(json!({})).await?;
        let resources = self.resources().await?;

        Ok(json!({
            "cell_id": self.cell_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "health": health,
            "containers": containers,
            "resources": resources
        }))
    }

    async fn containers(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let all = args.get("all")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        let mut cmd_args = vec!["ps", "--format", "{{.Names}}\t{{.Status}}\t{{.Ports}}"];
        if all {
            cmd_args.insert(1, "-a");
        }

        let output = Command::new("docker")
            .args(&cmd_args)
            .output();

        match output {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                let containers: Vec<serde_json::Value> = stdout
                    .lines()
                    .filter(|line| !line.is_empty())
                    .map(|line| {
                        let parts: Vec<&str> = line.split('\t').collect();
                        json!({
                            "name": parts.first().unwrap_or(&""),
                            "status": parts.get(1).unwrap_or(&""),
                            "ports": parts.get(2).unwrap_or(&"")
                        })
                    })
                    .collect();

                Ok(json!({
                    "cell_id": self.cell_id,
                    "container_count": containers.len(),
                    "containers": containers,
                    "include_stopped": all
                }))
            }
            Err(e) => {
                Ok(json!({
                    "cell_id": self.cell_id,
                    "error": format!("Failed to list containers: {}", e),
                    "containers": []
                }))
            }
        }
    }

    async fn resources(&self) -> Result<serde_json::Value> {
        // Get CPU info
        let cpu_output = Command::new("sh")
            .args(["-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' 2>/dev/null || echo '0'"])
            .output();
        
        let cpu_usage = cpu_output
            .ok()
            .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse::<f64>().ok())
            .unwrap_or(0.0);

        // Get memory info
        let mem_output = Command::new("sh")
            .args(["-c", "free -m | awk 'NR==2{printf \"%d %d %.2f\", $3,$2,$3*100/$2}'"])
            .output();
        
        let mem_info = mem_output
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();
        let mem_parts: Vec<&str> = mem_info.split_whitespace().collect();

        // Get disk info
        let disk_output = Command::new("sh")
            .args(["-c", "df -h / | awk 'NR==2{print $3,$2,$5}'"])
            .output();
        
        let disk_info = disk_output
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();
        let disk_parts: Vec<&str> = disk_info.split_whitespace().collect();

        Ok(json!({
            "cell_id": self.cell_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "cpu": {
                "usage_percent": cpu_usage
            },
            "memory": {
                "used_mb": mem_parts.first().and_then(|s| s.parse::<i64>().ok()).unwrap_or(0),
                "total_mb": mem_parts.get(1).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0),
                "usage_percent": mem_parts.get(2).and_then(|s| s.parse::<f64>().ok()).unwrap_or(0.0)
            },
            "disk": {
                "used": disk_parts.first().unwrap_or(&"0"),
                "total": disk_parts.get(1).unwrap_or(&"0"),
                "usage_percent": disk_parts.get(2).unwrap_or(&"0%")
            }
        }))
    }

    async fn exec(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let command = args.get("command")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let working_dir = args.get("working_dir")
            .and_then(|v| v.as_str());

        // Safety check - block dangerous commands
        let dangerous = ["rm -rf /", "dd if=", "mkfs", "> /dev/", ":(){ :|:& };:"];
        if dangerous.iter().any(|d| command.contains(d)) {
            return Ok(json!({
                "command": command,
                "success": false,
                "error": "Command blocked for safety"
            }));
        }

        let mut cmd = Command::new("sh");
        cmd.args(["-c", command]);
        
        if let Some(dir) = working_dir {
            cmd.current_dir(dir);
        }

        let output = cmd.output();

        match output {
            Ok(out) => {
                Ok(json!({
                    "command": command,
                    "success": out.status.success(),
                    "exit_code": out.status.code(),
                    "stdout": String::from_utf8_lossy(&out.stdout).to_string(),
                    "stderr": String::from_utf8_lossy(&out.stderr).to_string()
                }))
            }
            Err(e) => {
                Ok(json!({
                    "command": command,
                    "success": false,
                    "error": format!("Execution failed: {}", e)
                }))
            }
        }
    }
}

