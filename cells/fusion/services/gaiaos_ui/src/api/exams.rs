//! Exam API Endpoints
//!
//! Provides endpoints to start and monitor live exams:
//! - POST /api/exams/start - Start a new exam
//! - GET /api/exams/:id/status - Get exam status

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;
use crate::AppState;

/// Request to start an exam
#[derive(Debug, Deserialize)]
pub struct StartExamRequest {
    #[serde(rename = "domainId")]
    pub domain_id: String,
    #[serde(rename = "numQuestions", default = "default_num_questions")]
    pub num_questions: usize,
    #[serde(default = "default_mode")]
    pub mode: String,
}

fn default_num_questions() -> usize { 10 }
fn default_mode() -> String { "standard".to_string() }

/// Response after starting an exam
#[derive(Debug, Serialize)]
pub struct StartExamResponse {
    #[serde(rename = "examId")]
    pub exam_id: String,
    #[serde(rename = "sessionId")]
    pub session_id: String,
    #[serde(rename = "domainId")]
    pub domain_id: String,
    #[serde(rename = "numQuestions")]
    pub num_questions: usize,
    pub mode: String,
    pub status: String,
    pub message: String,
}

/// Exam status response
#[derive(Debug, Serialize)]
pub struct ExamStatusResponse {
    #[serde(rename = "examId")]
    pub exam_id: String,
    pub status: String,
    #[serde(rename = "currentQuestion")]
    pub current_question: usize,
    #[serde(rename = "totalQuestions")]
    pub total_questions: usize,
    #[serde(rename = "correctCount")]
    pub correct_count: usize,
    #[serde(rename = "partialCount")]
    pub partial_count: usize,
    #[serde(rename = "incorrectCount")]
    pub incorrect_count: usize,
    pub accuracy: f32,
    #[serde(rename = "elapsedMs")]
    pub elapsed_ms: u64,
}

/// Start a new exam
pub async fn start_exam(
    State(_state): State<Arc<AppState>>,
    Json(req): Json<StartExamRequest>,
) -> impl IntoResponse {
    let exam_id = format!("EXAM-{}", Uuid::new_v4().to_string()[..8].to_uppercase());
    let session_id = Uuid::new_v4().to_string();
    
    // In a full implementation, this would:
    // 1. Store exam in state/database
    // 2. Spawn exam runner task
    // 3. Begin streaming events over WebSocket
    
    // For now, return the exam metadata
    let response = StartExamResponse {
        exam_id: exam_id.clone(),
        session_id,
        domain_id: req.domain_id.clone(),
        num_questions: req.num_questions,
        mode: req.mode.clone(),
        status: "started".to_string(),
        message: format!(
            "Exam started for domain '{}' with {} questions in '{}' mode. Events will stream over WebSocket.",
            req.domain_id, req.num_questions, req.mode
        ),
    };
    
    (StatusCode::OK, Json(response))
}

/// Get exam status
pub async fn get_exam_status(
    State(_state): State<Arc<AppState>>,
    Path(exam_id): Path<String>,
) -> impl IntoResponse {
    // In a full implementation, this would look up the exam state
    // For now, return a mock status
    
    let response = ExamStatusResponse {
        exam_id,
        status: "in_progress".to_string(),
        current_question: 3,
        total_questions: 10,
        correct_count: 2,
        partial_count: 1,
        incorrect_count: 0,
        accuracy: 83.3,
        elapsed_ms: 45000,
    };
    
    (StatusCode::OK, Json(response))
}

/// List all exam domains with their subdomains
pub async fn list_exam_domains() -> impl IntoResponse {
    let domains = serde_json::json!([
        {
            "id": "medical",
            "label": "Medical",
            "subdomains": ["Cardiology", "Pulmonology", "Nephrology", "Neurology", "Pharmacology"],
            "defaultQuestions": 20
        },
        {
            "id": "legal",
            "label": "Legal",
            "subdomains": ["Constitutional Law", "Criminal Law", "Contracts", "Torts", "Evidence"],
            "defaultQuestions": 15
        },
        {
            "id": "code",
            "label": "Code",
            "subdomains": ["Python", "Rust", "Algorithms", "System Design", "Security"],
            "defaultQuestions": 10
        },
        {
            "id": "finance",
            "label": "Finance",
            "subdomains": ["Portfolio Management", "Fixed Income", "Derivatives", "Corporate Finance"],
            "defaultQuestions": 15
        },
        {
            "id": "chemistry",
            "label": "Chemistry",
            "subdomains": ["Organic Chemistry", "Inorganic Chemistry", "Physical Chemistry", "Biochemistry"],
            "defaultQuestions": 15
        },
        {
            "id": "math",
            "label": "Math",
            "subdomains": ["Calculus", "Linear Algebra", "Statistics", "Number Theory"],
            "defaultQuestions": 10
        },
        {
            "id": "engineering",
            "label": "Engineering",
            "subdomains": ["Structural", "Thermodynamics", "Fluid Mechanics", "Circuits"],
            "defaultQuestions": 15
        },
        {
            "id": "mental_health",
            "label": "AI Therapist (Support Only)",
            "subdomains": ["Risk Assessment", "Crisis Escalation", "Empathy & Reflection", "Coping Skills", "Boundaries"],
            "defaultQuestions": 5,
            "riskTier": "critical",
            "safetyNotes": "Non-diagnostic, non-prescribing, emergency-escalating. All responses FoT-audited."
        }
    ]);
    
    (StatusCode::OK, Json(domains))
}
