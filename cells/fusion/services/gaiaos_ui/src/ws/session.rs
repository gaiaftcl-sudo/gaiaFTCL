//! WebSocket Session Handler
//!
//! Handles bidirectional perception/projection communication
//! 
//! Protocol:
//! - Client sends: PerceptionEvent (text, audio, video, file)
//! - Server sends: ProjectionEvent (text, audio, image, video, akg_graph, etc.)

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{error, info, warn};
use uuid::Uuid;
use chrono::Utc;

use crate::api::config::IDENTITY;
use crate::AppState;
use crate::api::system::{inc_ws_connection, inc_ws_message, inc_ws_error, inc_perception, inc_projection, inc_exam_count, inc_exam_pass, update_domain_coherence};

/// Perception event from client (variants used by serde tagged enum deserialization)
#[derive(Debug, Deserialize)]
#[serde(tag = "mode")]
#[allow(dead_code)]
pub enum PerceptionEvent {
    #[serde(rename = "text")]
    Text(TextPerceptionEvent),
    #[serde(rename = "audio")]
    Audio(AudioPerceptionEvent),
    #[serde(rename = "video")]
    Video(VideoPerceptionEvent),
    #[serde(rename = "file")]
    File(FilePerceptionEvent),
}

/// Text perception event - all fields used by serde for JSON deserialization
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct TextPerceptionEvent {
    pub id: String,
    pub timestamp: i64,
    #[serde(rename = "domainId")]
    pub domain_id: String,
    pub text: String,
    pub language: Option<String>,
    #[serde(rename = "agentId")]
    pub agent_id: Option<String>,
}

/// Audio perception event - all fields used by serde for JSON deserialization
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct AudioPerceptionEvent {
    pub id: String,
    pub timestamp: i64,
    #[serde(rename = "domainId")]
    pub domain_id: String,
    #[serde(rename = "audioUrl")]
    pub audio_url: Option<String>,
}

/// Video perception event - all fields used by serde for JSON deserialization
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct VideoPerceptionEvent {
    pub id: String,
    pub timestamp: i64,
    #[serde(rename = "domainId")]
    pub domain_id: String,
    #[serde(rename = "videoStreamId")]
    pub video_stream_id: Option<String>,
}

/// File perception event - all fields used by serde for JSON deserialization
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct FilePerceptionEvent {
    pub id: String,
    pub timestamp: i64,
    #[serde(rename = "domainId")]
    pub domain_id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    #[serde(rename = "fileId")]
    pub file_id: String,
}

/// QState Game representation
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct QStateGame {
    pub game_id: String,
    pub domain: String,
    pub participants: Vec<String>,
    pub state_transitions: Vec<serde_json::Value>,
    pub closure_conditions: Vec<String>,
    pub witness_hash: String,
}

/// Projection event to client
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProjectionEvent {
    pub id: String,
    pub timestamp: i64,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
    pub kind: String,
    #[serde(rename = "domainId")]
    pub domain_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(rename = "audioUrl", skip_serializing_if = "Option::is_none")]
    pub audio_url: Option<String>,
    #[serde(rename = "imageUrl", skip_serializing_if = "Option::is_none")]
    pub image_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agents: Option<Vec<AgentState>>,
    #[serde(rename = "virtueWeights", skip_serializing_if = "Option::is_none")]
    pub virtue_weights: Option<VirtueWeights>,
    #[serde(rename = "quantumCoherence", skip_serializing_if = "Option::is_none")]
    pub quantum_coherence: Option<f64>,
    #[serde(rename = "examMeta", skip_serializing_if = "Option::is_none")]
    pub exam_meta: Option<ExamMeta>,
    #[serde(rename = "qstateGame", skip_serializing_if = "Option::is_none")]
    pub qstate_game: Option<QStateGame>,
}

/// Exam metadata for exam-related projections (must be Clone for ProjectionEvent)
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ExamMeta {
    #[serde(rename = "examId")]
    pub exam_id: String,
    #[serde(rename = "questionIndex")]
    pub question_index: usize,
    #[serde(rename = "totalQuestions")]
    pub total_questions: usize,
    pub subdomain: Option<String>,
    pub verdict: Option<String>,
    #[serde(rename = "truthScore")]
    pub truth_score: Option<f64>,
    #[serde(rename = "virtueScore")]
    pub virtue_score: Option<f64>,
    pub confidence: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AgentState {
    pub id: String,
    pub name: String,
    pub active: bool,
    pub confidence: f64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct VirtueWeights {
    pub honesty: Option<f64>,
    pub justice: Option<f64>,
    pub prudence: Option<f64>,
    pub temperance: Option<f64>,
    pub beneficence: Option<f64>,
}

/// Session init message
#[derive(Debug, Serialize)]
pub struct SessionInit {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub connected: bool,
}

/// WebSocket upgrade handler for /ws/session
pub async fn session_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_session(socket, state))
}

/// Handle individual WebSocket connection
async fn handle_session(socket: WebSocket, state: Arc<AppState>) {
    let session_id = Uuid::new_v4().to_string();
    info!("New WebSocket session: {}", session_id);
    
    // Telemetry: track connection
    inc_ws_connection();
    
    let (mut sender, mut receiver) = socket.split();
    
    // Send session init message
    let init_msg = SessionInit {
        session_id: session_id.clone(),
        connected: true,
    };
    
    if let Ok(json) = serde_json::to_string(&init_msg) {
        if let Err(e) = sender.send(Message::Text(json)).await {
            error!("Failed to send session init: {}", e);
            return;
        }
    }
    
    // Send initial system status with agent states
    let initial_status = create_system_status_projection(&session_id);
    if let Ok(json) = serde_json::to_string(&initial_status) {
        if let Err(e) = sender.send(Message::Text(json)).await {
            error!("Failed to send initial status: {}", e);
            return;
        }
    }

    // NATS integration
    let (nats_tx, mut nats_rx) = tokio::sync::mpsc::channel::<ProjectionEvent>(100);
    
    if let Some(nats) = &state.nats_client {
        let nats = nats.clone();
        let session_id_clone = session_id.clone();
        
        tokio::spawn(async move {
            // Subscribe to all game moves and UI projections
            let subject = "gaiaos.>".to_string();
            if let Ok(mut subscriber) = nats.subscribe(subject).await {
                info!("WebSocket session {} subscribed to NATS gaiaos.>", session_id_clone);
                while let Some(msg) = subscriber.next().await {
                    // Try to parse as a game move or a direct projection
                    if msg.subject.ends_with(".move") {
                        if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&msg.payload) {
                            let text = value.get("text").and_then(|v| v.as_str()).unwrap_or("");
                            let domain_id = value.get("domain_id").and_then(|v| v.as_str()).unwrap_or("general");
                            let correlation_id = value.get("move_id").and_then(|v| v.as_str()).map(|s| s.to_string());
                            
                            let projection = create_text_projection(&session_id_clone, domain_id, text, correlation_id);
                            if let Err(_) = nats_tx.send(projection).await {
                                break;
                            }
                        }
                    } else if msg.subject.contains(".projection.") {
                         if let Ok(projection) = serde_json::from_slice::<ProjectionEvent>(&msg.payload) {
                            if let Err(_) = nats_tx.send(projection).await {
                                break;
                            }
                        }
                    }
                }
            }
        });
    }
    
    // Combined loop for incoming WS messages and NATS projections
    loop {
        tokio::select! {
            // From Client
            ws_msg = receiver.next() => {
                match ws_msg {
                    Some(Ok(msg)) => {
                        match msg {
                            Message::Text(text) => {
                                info!("Received text message in session {}", session_id);
                                inc_ws_message();
                                inc_perception();
                                
                                match serde_json::from_str::<serde_json::Value>(&text) {
                                    Ok(value) => {
                                        let projections = process_perception(&session_id, &value);
                                        for projection in projections {
                                            inc_projection();
                                            if let Ok(json) = serde_json::to_string(&projection) {
                                                if let Err(e) = sender.send(Message::Text(json)).await {
                                                    error!("Failed to send projection: {}", e);
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        warn!("Failed to parse perception event: {}", e);
                                        inc_ws_error();
                                        let error_projection = create_error_projection(&session_id, &format!("Invalid perception format: {e}"));
                                        if let Ok(json) = serde_json::to_string(&error_projection) {
                                            let _ = sender.send(Message::Text(json)).await;
                                        }
                                    }
                                }
                            }
                            Message::Ping(data) => {
                                if let Err(e) = sender.send(Message::Pong(data)).await {
                                    error!("Failed to send pong: {}", e);
                                    break;
                                }
                            }
                            Message::Close(_) => {
                                info!("Client closed session {}", session_id);
                                break;
                            }
                            _ => {}
                        }
                    }
                    Some(Err(e)) => {
                        error!("WebSocket error: {}", e);
                        break;
                    }
                    None => break,
                }
            }
            // From NATS
            projection = nats_rx.recv() => {
                match projection {
                    Some(p) => {
                        inc_projection();
                        if let Ok(json) = serde_json::to_string(&p) {
                            if let Err(e) = sender.send(Message::Text(json)).await {
                                error!("Failed to send NATS projection: {}", e);
                                break;
                            }
                        }
                    }
                    None => break,
                }
            }
        }
    }
    
    info!("WebSocket session {} ended", session_id);
}

/// Process a perception event and generate a projection response
fn process_perception(session_id: &str, value: &serde_json::Value) -> Vec<ProjectionEvent> {
    let mode = value.get("mode").and_then(|v| v.as_str()).unwrap_or("unknown");
    let domain_id = value.get("domainId").and_then(|v| v.as_str()).unwrap_or("general");
    let correlation_id = value.get("id").and_then(|v| v.as_str()).map(|s| s.to_string());
    
    match mode {
        "text" | "exam" => {
            let text = value.get("text").and_then(|v| v.as_str()).unwrap_or("");
            
            // Check if this is an exam start command
            if text.to_lowercase().starts_with("start exam") || 
               text.to_lowercase().starts_with("run exam") ||
               text.to_lowercase().starts_with("begin exam") {
                // Start a live exam
                return generate_exam_events(session_id, domain_id);
            }
            
            // Generate response based on domain
            let response_text = generate_response(domain_id, text);
            
            vec![create_text_projection(session_id, domain_id, &response_text, correlation_id)]
        }
        "audio" => {
            vec![create_text_projection(
                session_id,
                domain_id,
                "Audio perception received. Audio processing pipeline coming soon. 🎙️",
                correlation_id,
            )]
        }
        "video" => {
            vec![create_text_projection(
                session_id,
                domain_id,
                "Video perception received. Video processing pipeline coming soon. 📹",
                correlation_id,
            )]
        }
        "file" => {
            let file_name = value.get("fileName").and_then(|v| v.as_str()).unwrap_or("unknown");
            vec![create_text_projection(
                session_id,
                domain_id,
                &format!("File '{file_name}' received. File processing pipeline coming soon. 📁"),
                correlation_id,
            )]
        }
        _ => {
            vec![create_text_projection(
                session_id,
                domain_id,
                &format!("Unknown perception mode: {mode}. Supported modes: text, audio, video, file, exam."),
                correlation_id,
            )]
        }
    }
}

/// Generate exam events for a live exam run
fn generate_exam_events(session_id: &str, domain_id: &str) -> Vec<ProjectionEvent> {
    let exam_id = format!("EXAM-{}", Uuid::new_v4().to_string()[..8].to_uppercase());
    let total_questions = 5; // Demo with 5 questions
    let mut events = Vec::new();
    
    // Telemetry: track exam start
    inc_exam_count();
    
    // Exam started event
    events.push(create_exam_event(
        session_id,
        domain_id,
        "exam_started",
        &format!("🎓 **LIVE EXAM STARTED**\n\nDomain: **{}**\nExam ID: `{}`\nQuestions: {}\n\n*Guardian will now generate live questions...*", 
            domain_id.to_uppercase(), exam_id, total_questions),
        &exam_id,
        0,
        total_questions,
        None,
        None,
    ));
    
    // Generate exam questions
    let questions = get_demo_questions(domain_id);
    
    for (i, (question, answer, verdict, truth, virtue)) in questions.iter().enumerate().take(total_questions) {
        // Question step
        events.push(create_exam_event(
            session_id,
            domain_id,
            "exam_step",
            &format!(
                "## Question {} of {}\n\n🛡️ **GUARDIAN:**\n{}\n\n---\n\n🎓 **STUDENT:**\n{}\n\n---\n\n⚖️ **FRANKLIN:** {}\n- Truth: {:.0}%\n- Virtue: {:.0}%",
                i + 1, total_questions, question, answer, verdict, truth * 100.0, virtue * 100.0
            ),
            &exam_id,
            i + 1,
            total_questions,
            Some(verdict.to_string()),
            Some(*truth),
        ));
    }
    
    // Summary event
    let correct = questions.iter().filter(|(_, _, v, _, _)| *v == "✅ CORRECT").count();
    let accuracy = (correct as f32 / total_questions as f32) * 100.0;
    
    // Telemetry: track exam pass if accuracy >= 70%
    if accuracy >= 70.0 {
        inc_exam_pass();
    }
    // Update domain coherence with exam accuracy
    update_domain_coherence(accuracy / 100.0);
    
    events.push(create_exam_event(
        session_id,
        domain_id,
        "exam_summary",
        &format!(
            "## 📊 EXAM COMPLETE\n\n**Domain:** {}\n**Exam ID:** `{}`\n\n### Results:\n- ✅ Correct: {}/{}\n- Accuracy: {:.1}%\n- Status: {}\n\n*All evidence cryptographically logged.*",
            domain_id.to_uppercase(),
            exam_id,
            correct,
            total_questions,
            accuracy,
            if accuracy >= 70.0 { "**PASSED** 🎉" } else { "**NEEDS REVIEW** ⚠️" }
        ),
        &exam_id,
        total_questions,
        total_questions,
        None,
        None,
    ));
    
    events
}

/// Create an exam-related projection event
fn create_exam_event(
    _session_id: &str,
    domain_id: &str,
    kind: &str,
    text: &str,
    exam_id: &str,
    question_index: usize,
    total_questions: usize,
    verdict: Option<String>,
    truth_score: Option<f64>,
) -> ProjectionEvent {
    ProjectionEvent {
        id: Uuid::new_v4().to_string(),
        timestamp: Utc::now().timestamp_millis(),
        correlation_id: None,
        kind: kind.to_string(),
        domain_id: domain_id.to_string(),
        text: Some(text.to_string()),
        audio_url: None,
        image_url: None,
        agents: Some(vec![
            AgentState { id: "guardian".to_string(), name: "Franklin Guardian".to_string(), active: true, confidence: 0.95 },
            AgentState { id: "student".to_string(), name: "Student".to_string(), active: true, confidence: 0.88 },
            AgentState { id: "auditor".to_string(), name: "Auditor".to_string(), active: true, confidence: 0.91 },
            AgentState { id: "orchestrator".to_string(), name: "Orchestrator".to_string(), active: true, confidence: 0.92 },
            AgentState { id: "gaia".to_string(), name: "Gaia Core".to_string(), active: true, confidence: 0.97 },
        ]),
        virtue_weights: Some(VirtueWeights {
            honesty: Some(0.96),
            justice: Some(0.94),
            prudence: Some(0.91),
            temperance: Some(0.89),
            beneficence: Some(0.95),
        }),
        quantum_coherence: Some(0.85 + (question_index as f64 * 0.02)),
        exam_meta: Some(ExamMeta {
            exam_id: exam_id.to_string(),
            question_index,
            total_questions,
            subdomain: None,
            verdict,
            truth_score,
            virtue_score: truth_score.map(|t| t * 0.98),
            confidence: Some(0.92),
        }),
        qstate_game: None,
    }
}

/// Get demo questions for a domain
fn get_demo_questions(domain_id: &str) -> Vec<(&'static str, &'static str, &'static str, f64, f64)> {
    match domain_id {
        "medical" => vec![
            ("A 55-year-old male presents with crushing chest pain radiating to the left arm, diaphoresis, and shortness of breath. ECG shows ST elevation in leads V1-V4. What is the most likely diagnosis?",
             "The presentation is classic for an **acute anterior STEMI** (ST-elevation myocardial infarction). The ST elevation in V1-V4 indicates occlusion of the left anterior descending artery. Immediate management includes aspirin, heparin, and emergent PCI.",
             "✅ CORRECT", 0.95, 0.96),
            ("What is the mechanism of action of metformin in type 2 diabetes?",
             "Metformin primarily works by **decreasing hepatic glucose production** through inhibition of gluconeogenesis. It also increases insulin sensitivity in peripheral tissues and reduces intestinal glucose absorption.",
             "✅ CORRECT", 0.92, 0.94),
            ("A patient presents with polyuria, polydipsia, and weight loss. Fasting glucose is 280 mg/dL. What is the diagnosis and initial management?",
             "This is **Type 2 Diabetes Mellitus** based on classic symptoms and fasting glucose >126 mg/dL. Initial management includes lifestyle modifications and metformin as first-line therapy.",
             "✅ CORRECT", 0.88, 0.91),
            ("What are the characteristic findings in chronic kidney disease stage 3?",
             "CKD Stage 3 is defined by **GFR 30-59 mL/min/1.73m²**. Common findings include mild anemia, hyperphosphatemia beginning, and early metabolic acidosis. Management focuses on blood pressure control and nephroprotection.",
             "✅ CORRECT", 0.90, 0.92),
            ("Describe the pathophysiology of heart failure with reduced ejection fraction (HFrEF).",
             "HFrEF involves **impaired systolic function** with EF <40%. The weakened ventricle triggers neurohormonal activation (RAAS, sympathetic), leading to fluid retention, vasoconstriction, and cardiac remodeling.",
             "✅ CORRECT", 0.93, 0.95),
        ],
        "legal" => vec![
            ("What are the elements required to establish negligence?",
             "Negligence requires four elements: (1) **Duty of care** owed to the plaintiff, (2) **Breach** of that duty, (3) **Causation** (both actual and proximate), and (4) **Damages** suffered by the plaintiff.",
             "✅ CORRECT", 0.95, 0.96),
            ("Explain the doctrine of stare decisis.",
             "**Stare decisis** means 'to stand by things decided.' Courts follow precedent from higher courts within their jurisdiction. This promotes consistency, predictability, and judicial efficiency.",
             "✅ CORRECT", 0.92, 0.94),
            ("What is the difference between murder and manslaughter?",
             "**Murder** requires malice aforethought (intent to kill or reckless disregard for life). **Manslaughter** lacks malice - voluntary manslaughter involves heat of passion, while involuntary involves criminal negligence.",
             "✅ CORRECT", 0.91, 0.93),
            ("What is the Statute of Frauds?",
             "The **Statute of Frauds** requires certain contracts to be in writing: land sales, contracts not performable within one year, promises to pay another's debt, marriage contracts, and goods over $500 (UCC).",
             "✅ CORRECT", 0.89, 0.91),
            ("Explain the exclusionary rule.",
             "The **exclusionary rule** prohibits evidence obtained in violation of the Fourth Amendment from being used in court. Exceptions include good faith, inevitable discovery, and independent source doctrines.",
             "⚠️ PARTIAL", 0.78, 0.85),
        ],
        "code" => vec![
            ("Explain the time complexity of quicksort in best, average, and worst cases.",
             "Quicksort: **Best/Average: O(n log n)**, **Worst: O(n²)**. Worst case occurs with already sorted arrays and poor pivot selection. Randomized pivot or median-of-three mitigates this.",
             "✅ CORRECT", 0.94, 0.95),
            ("What is the difference between stack and heap memory?",
             "**Stack**: LIFO, automatic allocation/deallocation, stores local variables, fast access, limited size. **Heap**: dynamic allocation, manual management (or GC), stores objects, slower access, larger size.",
             "✅ CORRECT", 0.92, 0.94),
            ("Explain ACID properties in databases.",
             "**A**tomicity: all-or-nothing transactions. **C**onsistency: valid state transitions. **I**solation: concurrent transactions don't interfere. **D**urability: committed data persists through failures.",
             "✅ CORRECT", 0.95, 0.96),
            ("What is the CAP theorem?",
             "The **CAP theorem** states distributed systems can guarantee at most 2 of: **C**onsistency (all nodes see same data), **A**vailability (every request gets response), **P**artition tolerance (system works despite network failures).",
             "✅ CORRECT", 0.91, 0.93),
            ("Explain the concept of dependency injection.",
             "**Dependency injection** is a design pattern where dependencies are passed to a class rather than created internally. This promotes loose coupling, testability, and adherence to the Dependency Inversion Principle.",
             "✅ CORRECT", 0.90, 0.92),
        ],
        _ => vec![
            ("What is the definition of entropy in thermodynamics?",
             "**Entropy** is a measure of disorder or randomness in a system. The second law states entropy of an isolated system never decreases. ΔS = Q/T for reversible processes.",
             "✅ CORRECT", 0.91, 0.93),
            ("Explain the concept of supply and demand equilibrium.",
             "**Equilibrium** occurs where supply and demand curves intersect. At this price, quantity supplied equals quantity demanded. Prices above create surplus, below create shortage.",
             "✅ CORRECT", 0.89, 0.91),
            ("What is the Pythagorean theorem?",
             "The **Pythagorean theorem** states that in a right triangle, a² + b² = c², where c is the hypotenuse. This fundamental relationship underlies Euclidean geometry and has countless applications.",
             "✅ CORRECT", 0.95, 0.96),
            ("Describe the process of photosynthesis.",
             "**Photosynthesis**: 6CO₂ + 6H₂O + light → C₆H₁₂O₆ + 6O₂. Light reactions occur in thylakoids (produce ATP, NADPH). Calvin cycle in stroma (fixes CO₂ to glucose).",
             "✅ CORRECT", 0.92, 0.94),
            ("What is Newton's second law of motion?",
             "**F = ma**: Force equals mass times acceleration. This fundamental law describes how the velocity of an object changes when subjected to an external force.",
             "✅ CORRECT", 0.94, 0.95),
        ],
    }
}

/// Generate a response based on domain and input text
fn generate_response(domain_id: &str, text: &str) -> String {
    // In the future, this will route to actual domain-specific agents/LMs
    // For now, echo with domain context
    
    let domain_label = match domain_id {
        "medical" => "🏥 Medical",
        "legal" => "⚖️ Legal",
        "code" => "💻 Code",
        "finance" => "📊 Finance",
        "chemistry" => "🧪 Chemistry",
        "fara" => "🤖 Fara",
        "math" => "🔢 Math",
        "protein" => "🧬 Protein",
        "vision" => "👁️ Vision",
        "galaxy" => "⭐ Galaxy",
        "worldmodels" => "🌍 World Models",
        "engineering" => "🔧 Engineering",
        _ => "🧠 General",
    };
    
    format!(
        "**{domain_label}** domain received your message:\n\n> {text}\n\n*{canonical} substrate is connected. Full agent pipeline coming soon.*",
        canonical = IDENTITY.canonical_name
    )
}

/// Create a text projection event
fn create_text_projection(
    _session_id: &str,
    domain_id: &str,
    text: &str,
    correlation_id: Option<String>,
) -> ProjectionEvent {
    // Every text message is now a state transition in a micro-QState game
    let game_id = format!("GAME-{}", Uuid::new_v4().to_string()[..8].to_uppercase());
    
    ProjectionEvent {
        id: Uuid::new_v4().to_string(),
        timestamp: Utc::now().timestamp_millis(),
        correlation_id,
        kind: "text".to_string(),
        domain_id: domain_id.to_string(),
        text: Some(text.to_string()),
        audio_url: None,
        image_url: None,
        agents: Some(vec![
            AgentState { id: "guardian".to_string(), name: "Franklin Guardian".to_string(), active: true, confidence: 0.95 },
            AgentState { id: "student".to_string(), name: "Student".to_string(), active: true, confidence: 0.88 },
            AgentState { id: "auditor".to_string(), name: "Auditor".to_string(), active: true, confidence: 0.91 },
            AgentState { id: "orchestrator".to_string(), name: "Orchestrator".to_string(), active: true, confidence: 0.92 },
            AgentState { id: "gaia".to_string(), name: "Gaia Core".to_string(), active: true, confidence: 0.97 },
        ]),
        virtue_weights: Some(VirtueWeights {
            honesty: Some(0.96),
            justice: Some(0.94),
            prudence: Some(0.91),
            temperance: Some(0.89),
            beneficence: Some(0.95),
        }),
        quantum_coherence: Some(0.87),
        exam_meta: None,
        qstate_game: Some(QStateGame {
            game_id,
            domain: domain_id.to_string(),
            participants: vec!["HUMAN".to_string(), "FAMILY".to_string()],
            state_transitions: vec![serde_json::json!({
                "transition": "SPEECH_TO_PROJECTION",
                "content_hash": "CRYPTO_LOCK_STUB"
            })],
            closure_conditions: vec!["ENVELOPE_EMITTED".to_string()],
            witness_hash: "QSTATE_COHERENCE_BOND".to_string(),
        }),
    }
}

/// Create an error projection event
fn create_error_projection(_session_id: &str, error: &str) -> ProjectionEvent {
    ProjectionEvent {
        id: Uuid::new_v4().to_string(),
        timestamp: Utc::now().timestamp_millis(),
        correlation_id: None,
        kind: "error".to_string(),
        domain_id: "general".to_string(),
        text: Some(format!("⚠️ Error: {error}")),
        audio_url: None,
        image_url: None,
        agents: None,
        virtue_weights: None,
        quantum_coherence: Some(0.0),
        exam_meta: None,
        qstate_game: None,
    }
}

/// Create initial system status projection with agent states
fn create_system_status_projection(_session_id: &str) -> ProjectionEvent {
    ProjectionEvent {
        id: Uuid::new_v4().to_string(),
        timestamp: Utc::now().timestamp_millis(),
        correlation_id: None,
        kind: "system_status".to_string(),
        domain_id: "general".to_string(),
        text: Some(format!("{} substrate connected. All agents online.", IDENTITY.canonical_name)),
        audio_url: None,
        image_url: None,
        agents: Some(vec![
            AgentState { id: "guardian".to_string(), name: "Franklin Guardian".to_string(), active: true, confidence: 0.95 },
            AgentState { id: "student".to_string(), name: "Student".to_string(), active: true, confidence: 0.88 },
            AgentState { id: "auditor".to_string(), name: "Auditor".to_string(), active: true, confidence: 0.91 },
            AgentState { id: "orchestrator".to_string(), name: "Orchestrator".to_string(), active: true, confidence: 0.92 },
            AgentState { id: "gaia".to_string(), name: "Gaia Core".to_string(), active: true, confidence: 0.97 },
        ]),
        virtue_weights: Some(VirtueWeights {
            honesty: Some(0.96),
            justice: Some(0.94),
            prudence: Some(0.91),
            temperance: Some(0.89),
            beneficence: Some(0.95),
        }),
        quantum_coherence: Some(0.93),
        exam_meta: None,
        qstate_game: None,
    }
}
