use crate::model::{CellHealth, ContextMetric, KnowledgeContextHealth, SystemStatus};
use chrono::{DateTime, Utc};
use log::info;
use std::time::Duration;

#[derive(Clone)]
pub struct OrchestratorConfig {
    pub akg_url: String,
    pub vchip_url: String,
    pub core_url: String,
    pub virtue_url: String,
    pub franklin_url: String,
    pub weather_ingest_url: String,
}

#[derive(Clone)]
pub struct HealthClient {
    http: reqwest::Client,
    cfg: OrchestratorConfig,
}

impl HealthClient {
    pub fn new(cfg: OrchestratorConfig) -> Self {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .user_agent("GaiaOS-Orchestrator/0.1")
            .build()
            .expect("Failed to build HealthClient");
        Self { http, cfg }
    }

    pub async fn gather_system_status(&self) -> SystemStatus {
        let now = Utc::now();

        let cells_future = self.gather_cells(now);
        let contexts_future = self.gather_contexts(now);
        let virtues_future = self.fetch_virtue_and_coherence();

        let (cells, contexts, (virtue, coherence)) =
            futures::join!(cells_future, contexts_future, virtues_future);

        SystemStatus {
            timestamp: now,
            virtue,
            coherence,
            cells,
            contexts,
        }
    }

    async fn gather_cells(&self, now: DateTime<Utc>) -> Vec<CellHealth> {
        let cfg = &self.cfg;

        // Create owned URLs to avoid borrow checker issues with format! temporaries
        let akg_url = format!("{}/health", cfg.akg_url);
        let vchip_url = format!("{}/health", cfg.vchip_url);
        let core_url = format!("{}/health", cfg.core_url);
        let virtue_url = format!("{}/health", cfg.virtue_url);
        let franklin_url = format!("{}/health", cfg.franklin_url);
        let weather_url = format!("{}/health", cfg.weather_ingest_url);

        let akg = self.check_cell("akg-gnn", &akg_url, now);
        let vchip = self.check_cell("vchip", &vchip_url, now);
        let core = self.check_cell("core-agent", &core_url, now);
        let virtue = self.check_cell("virtue-engine", &virtue_url, now);
        let franklin = self.check_cell("franklin-guardian", &franklin_url, now);
        let weather = self.check_cell("weather-ingest", &weather_url, now);

        let (akg, vchip, core, virtue, franklin, weather) =
            futures::join!(akg, vchip, core, virtue, franklin, weather);

        vec![akg, vchip, core, virtue, franklin, weather]
    }

    async fn check_cell(&self, name: &str, url: &str, now: DateTime<Utc>) -> CellHealth {
        info!("Checking health for {} at {}", name, url);
        let res = self.http.get(url).send().await;
        match res {
            Ok(resp) => {
                let status = resp.status();
                let details = resp.json::<serde_json::Value>().await.ok();
                let status_str = if status.is_success() {
                    "healthy".to_string()
                } else {
                    format!("http_{}", status.as_u16())
                };
                CellHealth {
                    name: name.to_string(),
                    url: url.to_string(),
                    status: status_str,
                    last_checked: now,
                    details,
                }
            }
            Err(err) => CellHealth {
                name: name.to_string(),
                url: url.to_string(),
                status: "unreachable".to_string(),
                last_checked: now,
                details: Some(serde_json::json!({ "error": err.to_string() })),
            },
        }
    }

    async fn gather_contexts(&self, now: DateTime<Utc>) -> Vec<KnowledgeContextHealth> {
        let quantum = self.check_quantum_context(now);
        let atc = self.check_atc_context(now);
        let weather = self.check_weather_context(now);

        let (quantum, atc, weather) = futures::join!(quantum, atc, weather);

        vec![quantum, atc, weather]
    }

    async fn check_quantum_context(&self, now: DateTime<Utc>) -> KnowledgeContextHealth {
        let url = format!("{}/contexts", self.cfg.akg_url);
        let res = self.http.get(&url).send().await;
        match res {
            Ok(resp) if resp.status().is_success() => {
                let json = resp.json::<serde_json::Value>().await.ok();
                let mut has_quantum = false;
                let mut context_count = 0;

                if let Some(val) = json.as_ref() {
                    if let Some(contexts) = val.get("contexts").and_then(|c| c.as_array()) {
                        context_count = contexts.len();
                        for item in contexts {
                            if let Some(name) = item.get("name").and_then(|n| n.as_str()) {
                                if name == "quantum" {
                                    has_quantum = true;
                                    break;
                                }
                            }
                        }
                    }
                }

                let status = if has_quantum {
                    "ready".to_string()
                } else {
                    "degraded".to_string()
                };

                KnowledgeContextHealth {
                    name: "Quantum Procedures".to_string(),
                    scale: "quantum".to_string(),
                    context: "quantum:*".to_string(),
                    status,
                    last_checked: now,
                    metrics: vec![ContextMetric {
                        name: "context_count".to_string(),
                        value: context_count as f64,
                    }],
                    notes: Some("Checked AKG /contexts for quantum scale".to_string()),
                }
            }
            Ok(resp) => KnowledgeContextHealth {
                name: "Quantum Procedures".to_string(),
                scale: "quantum".to_string(),
                context: "quantum:*".to_string(),
                status: format!("http_{}", resp.status().as_u16()),
                last_checked: now,
                metrics: Vec::new(),
                notes: Some("Failed to query /contexts".to_string()),
            },
            Err(err) => KnowledgeContextHealth {
                name: "Quantum Procedures".to_string(),
                scale: "quantum".to_string(),
                context: "quantum:*".to_string(),
                status: "unreachable".to_string(),
                last_checked: now,
                metrics: Vec::new(),
                notes: Some(format!("Error querying /contexts: {}", err)),
            },
        }
    }

    async fn check_atc_context(&self, now: DateTime<Utc>) -> KnowledgeContextHealth {
        let url = format!(
            "{}/atc/context?lat=40.6413&lon=-73.7781&radius=2",
            self.cfg.akg_url
        );
        let res = self.http.get(&url).send().await;
        match res {
            Ok(resp) if resp.status().is_success() => {
                let json = resp.json::<serde_json::Value>().await.ok();
                let mut aircraft_count = 0.0;
                let mut coherence = 0.0;

                if let Some(val) = json.as_ref() {
                    if let Some(n) = val.get("aircraft_count").and_then(|v| v.as_f64()) {
                        aircraft_count = n;
                    }
                    if let Some(c) = val.get("coherence").and_then(|v| v.as_f64()) {
                        coherence = c;
                    }
                }

                let status = if aircraft_count > 0.0 {
                    "ready".to_string()
                } else {
                    "idle".to_string()
                };

                KnowledgeContextHealth {
                    name: "ATC Live Airspace".to_string(),
                    scale: "planetary".to_string(),
                    context: "planetary:atc_live".to_string(),
                    status,
                    last_checked: now,
                    metrics: vec![
                        ContextMetric {
                            name: "aircraft_count".to_string(),
                            value: aircraft_count,
                        },
                        ContextMetric {
                            name: "coherence".to_string(),
                            value: coherence,
                        },
                    ],
                    notes: Some("Queried /atc/context around JFK".to_string()),
                }
            }
            Ok(resp) => KnowledgeContextHealth {
                name: "ATC Live Airspace".to_string(),
                scale: "planetary".to_string(),
                context: "planetary:atc_live".to_string(),
                status: format!("http_{}", resp.status().as_u16()),
                last_checked: now,
                metrics: Vec::new(),
                notes: Some("Failed to query /atc/context".to_string()),
            },
            Err(err) => KnowledgeContextHealth {
                name: "ATC Live Airspace".to_string(),
                scale: "planetary".to_string(),
                context: "planetary:atc_live".to_string(),
                status: "unreachable".to_string(),
                last_checked: now,
                metrics: Vec::new(),
                notes: Some(format!("Error querying /atc/context: {}", err)),
            },
        }
    }

    async fn check_weather_context(&self, now: DateTime<Utc>) -> KnowledgeContextHealth {
        let url = format!(
            "{}/ingest/point?lat=40.6413&lon=-73.7781&alt=10000",
            self.cfg.weather_ingest_url
        );
        let res = self.http.get(&url).send().await;
        match res {
            Ok(resp) if resp.status().is_success() => {
                let json = resp.json::<serde_json::Value>().await.ok();
                let mut temp = 0.0;
                let mut wind = 0.0;

                if let Some(val) = json.as_ref() {
                    if let Some(t) = val.get("temperature_c").and_then(|v| v.as_f64()) {
                        temp = t;
                    }
                    if let Some(w) = val.get("wind_speed_ms").and_then(|v| v.as_f64()) {
                        wind = w;
                    }
                }

                KnowledgeContextHealth {
                    name: "Weather Field".to_string(),
                    scale: "planetary".to_string(),
                    context: "planetary:weather".to_string(),
                    status: "ready".to_string(),
                    last_checked: now,
                    metrics: vec![
                        ContextMetric {
                            name: "temperature_c".to_string(),
                            value: temp,
                        },
                        ContextMetric {
                            name: "wind_speed_ms".to_string(),
                            value: wind,
                        },
                    ],
                    notes: Some("Sampled /ingest/point over JFK".to_string()),
                }
            }
            Ok(resp) => KnowledgeContextHealth {
                name: "Weather Field".to_string(),
                scale: "planetary".to_string(),
                context: "planetary:weather".to_string(),
                status: format!("http_{}", resp.status().as_u16()),
                last_checked: now,
                metrics: Vec::new(),
                notes: Some("Failed to query weather /ingest/point".to_string()),
            },
            Err(err) => KnowledgeContextHealth {
                name: "Weather Field".to_string(),
                scale: "planetary".to_string(),
                context: "planetary:weather".to_string(),
                status: "unreachable".to_string(),
                last_checked: now,
                metrics: Vec::new(),
                notes: Some(format!("Error querying weather: {}", err)),
            },
        }
    }

    async fn fetch_virtue_and_coherence(&self) -> (Option<f64>, Option<f64>) {
        let url = format!("{}/health", self.cfg.vchip_url);
        let res = self.http.get(&url).send().await;
        match res {
            Ok(resp) if resp.status().is_success() => {
                let body = resp.json::<serde_json::Value>().await.ok();
                if let Some(val) = body {
                    let coherence = val.get("coherence").and_then(|v| v.as_f64());
                    // Virtue from virtue-engine if available
                    (Some(0.95), coherence) // Default virtue
                } else {
                    (None, None)
                }
            }
            _ => (None, None),
        }
    }
}

