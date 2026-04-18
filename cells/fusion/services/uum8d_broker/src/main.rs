use std::{collections::HashMap, net::SocketAddr, sync::Arc, time::Duration};

use anyhow::{anyhow, Context, Result};
use axum::{
    extract::{
        ws::{Message as WsFrame, WebSocket, WebSocketUpgrade},
        ConnectInfo, State,
    },
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use blake3::Hash as Blake3Hash;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use futures_util::{sink::SinkExt, stream::StreamExt};
use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, Mutex, RwLock};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{error, info, warn};
use url::Url;

use arangors::{
    client::reqwest::ReqwestClient, connection::Connection, database::Database, AqlQuery,
};
use tokio_tungstenite::tungstenite::{
    client::IntoClientRequest, http::HeaderValue, Message as TMessage,
};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct UUM8DMessage {
    pub id: String,
    pub timestamp_ms: i64,
    pub from_node: String,
    pub to_node: String,

    pub uum8d_payload: UUM8DPayload,

    pub signature_hex: String,
    pub pubkey_hex: String,

    pub constitutional_proof: ConstitutionalProof,

    pub priority: MessagePriority,
    pub ttl_seconds: u32,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct UUM8DPayload {
    // D1 routing
    pub routing_vector: [f32; 8],

    // D2 content
    pub content_encoding: String, // "json.zstd" / "bincode.zstd"
    pub content_bytes: Vec<u8>,   // compressed
    pub content_len_raw: u32,

    // D3 urgency
    pub energy_level: f32, // 0..1

    // D4 flow
    pub flow_pattern: FlowPattern,

    // D5 time window
    pub delivery_window_start_ms: Option<i64>,
    pub delivery_window_end_ms: Option<i64>,

    // D6 retry policy
    pub max_retries: u8,
    pub backoff_multiplier: f32,

    // D7 recipients
    pub recipients: Vec<String>,

    // D8 closure
    pub payload_hash_hex: String, // blake3 of compressed content_bytes
    pub compression_ratio: f32,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum FlowPattern {
    Direct,
    Broadcast,
    ConstitutionalChain,
    EventStream,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ConstitutionalProof {
    pub validator_node: String,
    pub validation_timestamp_ms: i64,
    pub virtue_scores: [f32; 4], // J,H,T,P
    pub approved: bool,
    pub proof_signature: String, // optional – fill later
}

impl ConstitutionalProof {
    pub fn auto_approved() -> Self {
        Self {
            validator_node: "auto".to_string(),
            validation_timestamp_ms: now_ms(),
            virtue_scores: [1.0, 1.0, 1.0, 1.0],
            approved: true,
            proof_signature: "".to_string(),
        }
    }
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum MessagePriority {
    Critical = 0,
    High = 1,
    Normal = 2,
    Low = 3,
}

type PeerTx = mpsc::Sender<UUM8DMessage>;

#[derive(Clone)]
struct AppState {
    node_id: String,
    db: Arc<Database<ReqwestClient>>,
    signing_key: Arc<Mutex<SigningKey>>,
    verifying_key: VerifyingKey,
    peers: Arc<RwLock<HashMap<String, PeerTx>>>,
}

#[derive(Deserialize)]
struct SendRequest {
    to_node: String,
    priority: Option<MessagePriority>,
    flow: Option<FlowPattern>,
    ttl_seconds: Option<u32>,
    body: serde_json::Value,
}

#[derive(Serialize)]
struct SendResponse {
    id: String,
    delivered_via: String, // "websocket" | "arango"
}

async fn health() -> impl IntoResponse {
    (StatusCode::OK, "ok")
}

async fn ws_upgrade(
    State(st): State<AppState>,
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
) -> impl IntoResponse {
    let remote_node = headers
        .get("x-node-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    info!("ws upgrade from {addr} remote_node={remote_node}");
    ws.on_upgrade(move |socket| ws_session(st, socket, remote_node))
}

async fn send_message(
    State(st): State<AppState>,
    Json(req): Json<SendRequest>,
) -> Result<Json<SendResponse>, (StatusCode, String)> {
    let priority = req.priority.unwrap_or(MessagePriority::Normal);
    let ttl_seconds = req.ttl_seconds.unwrap_or(300);
    let flow = req.flow.unwrap_or(FlowPattern::Direct);

    let raw =
        serde_json::to_vec(&req.body).map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;
    let compressed = zstd::encode_all(raw.as_slice(), 3)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("zstd: {e}")))?;

    let ratio = raw.len() as f32 / (compressed.len().max(1) as f32);
    let payload_hash = blake3::hash(&compressed);

    let msg_id = uuid::Uuid::new_v4().to_string();
    let payload = UUM8DPayload {
        routing_vector: compute_routing_vector(&req.to_node),
        content_encoding: "json.zstd".to_string(),
        content_bytes: compressed.clone(),
        content_len_raw: raw.len() as u32,
        energy_level: priority_to_energy(priority),
        flow_pattern: flow.clone(),
        delivery_window_start_ms: None,
        delivery_window_end_ms: Some(now_ms() + (ttl_seconds as i64 * 1000)),
        max_retries: 3,
        backoff_multiplier: 2.0,
        recipients: vec![req.to_node.clone()],
        payload_hash_hex: payload_hash.to_hex().to_string(),
        compression_ratio: ratio,
    };

    let constitutional_proof = if priority == MessagePriority::Critical
        || matches!(flow, FlowPattern::ConstitutionalChain)
    {
        constitutional_check(&st.node_id, &payload)
    } else {
        ConstitutionalProof::auto_approved()
    };

    let (sig_hex, pk_hex) = sign(&st, &msg_id, &payload)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let msg = UUM8DMessage {
        id: msg_id.clone(),
        timestamp_ms: now_ms(),
        from_node: st.node_id.clone(),
        to_node: req.to_node.clone(),
        uum8d_payload: payload,
        signature_hex: sig_hex,
        pubkey_hex: pk_hex,
        constitutional_proof,
        priority,
        ttl_seconds,
    };

    // Try direct WS delivery
    if let Some(tx) = st.peers.read().await.get(&req.to_node).cloned() {
        if tx.send(msg.clone()).await.is_ok() {
            record_delivered(&st, &msg, "websocket").await;
            return Ok(Json(SendResponse {
                id: msg_id,
                delivered_via: "websocket".to_string(),
            }));
        }
    }

    store_pending(&st, &msg)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    Ok(Json(SendResponse {
        id: msg_id,
        delivered_via: "arango".to_string(),
    }))
}

async fn ws_session(st: AppState, socket: WebSocket, remote_node: String) {
    let (tx, mut rx) = mpsc::channel::<UUM8DMessage>(256);

    st.peers.write().await.insert(remote_node.clone(), tx);
    info!("peer connected: {remote_node}");

    let (mut ws_sink, mut ws_stream) = socket.split();

    // Sender task
    let remote_node_for_send = remote_node.clone();
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match serde_json::to_string(&msg) {
                Ok(json) => {
                    if ws_sink.send(WsFrame::Text(json)).await.is_err() {
                        break;
                    }
                }
                Err(e) => {
                    warn!("ws serialize error peer={remote_node_for_send} err={e}");
                    break;
                }
            }
        }
    });

    // Receiver loop
    while let Some(frame) = ws_stream.next().await {
        match frame {
            Ok(WsFrame::Text(txt)) => match serde_json::from_str::<UUM8DMessage>(&txt) {
                Ok(msg) => match verify_and_accept(&st, &msg).await {
                    Ok(()) => {
                        deliver_local(&st, &msg).await;
                        record_delivered(&st, &msg, "websocket_in").await;
                    }
                    Err(err) => {
                        warn!(
                            "reject msg id={} from={} err={}",
                            msg.id, msg.from_node, err
                        );
                        record_failed(&st, &msg, &err).await;
                    }
                },
                Err(e) => warn!("ws parse error peer={remote_node} err={e}"),
            },
            Ok(WsFrame::Close(_)) => break,
            Ok(WsFrame::Binary(_)) => {}
            Ok(_) => {}
            Err(e) => {
                warn!("ws recv error peer={remote_node} err={e}");
                break;
            }
        }
    }

    st.peers.write().await.remove(&remote_node);
    info!("peer disconnected: {remote_node}");
    send_task.abort();
}

async fn poller_loop(st: AppState) {
    let node = st.node_id.clone();
    loop {
        match fetch_pending(&st, &node).await {
            Ok(msgs) => {
                for msg in msgs {
                    match verify_and_accept(&st, &msg).await {
                        Ok(()) => {
                            deliver_local(&st, &msg).await;
                            mark_pending_delivered(&st, &msg.id).await;
                            record_delivered(&st, &msg, "arango").await;
                        }
                        Err(err) => {
                            warn!("pending reject id={} err={}", msg.id, err);
                            record_failed(&st, &msg, &err).await;
                            mark_pending_failed(&st, &msg.id, &err).await;
                        }
                    }
                }
            }
            Err(e) => error!("poller error: {e}"),
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
}

#[derive(Debug, Clone)]
struct PeerSpec {
    peer_id: String,
    ws_url: String,
}

fn parse_peer_endpoints(env: &str) -> Vec<PeerSpec> {
    // Format:
    // - "peerId=host:port,peerId2=host2:port2"
    // - or "host:port,host2:port2" (peer_id defaults to host:port)
    let mut out = Vec::new();
    for raw in env.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()) {
        let (peer_id, addr) = match raw.split_once('=') {
            Some((a, b)) => (a.trim().to_string(), b.trim().to_string()),
            None => (raw.to_string(), raw.to_string()),
        };

        // accept:
        // - ws://host:port/ws
        // - http://host:port
        // - host:port
        let ws_url = if addr.starts_with("ws://") || addr.starts_with("wss://") {
            addr
        } else if addr.starts_with("http://") || addr.starts_with("https://") {
            format!("{}/ws", addr.trim_end_matches('/'))
        } else {
            format!("ws://{addr}/ws")
        };

        out.push(PeerSpec { peer_id, ws_url });
    }
    out
}

async fn peer_connector_loop(st: AppState, spec: PeerSpec) {
    // Dial-out reconnect loop for mesh formation.
    let mut backoff_ms: u64 = 250;
    loop {
        if spec.peer_id == st.node_id {
            tokio::time::sleep(Duration::from_secs(5)).await;
            continue;
        }

        // Validate URL format early so we don't spin hot on invalid values.
        if let Err(e) = Url::parse(&spec.ws_url) {
            warn!(
                "peer url invalid peer={} url={} err={e}",
                spec.peer_id, spec.ws_url
            );
            tokio::time::sleep(Duration::from_secs(5)).await;
            continue;
        }

        // Build request with x-node-id so the remote server registers us under our node_id.
        let mut req = match spec.ws_url.clone().into_client_request() {
            Ok(r) => r,
            Err(e) => {
                warn!(
                    "peer request build failed peer={} url={} err={e}",
                    spec.peer_id, spec.ws_url
                );
                tokio::time::sleep(Duration::from_secs(5)).await;
                continue;
            }
        };
        match HeaderValue::from_str(&st.node_id) {
            Ok(hv) => {
                req.headers_mut().insert("x-node-id", hv);
            }
            Err(_) => {
                req.headers_mut()
                    .insert("x-node-id", HeaderValue::from_static("unknown"));
            }
        }

        match tokio_tungstenite::connect_async(req).await {
            Ok((ws_stream, _resp)) => {
                info!(
                    "peer dial connected peer_id={} url={}",
                    spec.peer_id, spec.ws_url
                );
                backoff_ms = 250;

                let (tx, mut rx) = mpsc::channel::<UUM8DMessage>(256);
                st.peers.write().await.insert(spec.peer_id.clone(), tx);

                let (mut ws_sink, mut ws_stream) = ws_stream.split();

                let peer_id_for_send = spec.peer_id.clone();
                let send_task = tokio::spawn(async move {
                    while let Some(msg) = rx.recv().await {
                        match serde_json::to_string(&msg) {
                            Ok(json) => {
                                if ws_sink.send(TMessage::Text(json)).await.is_err() {
                                    break;
                                }
                            }
                            Err(e) => {
                                warn!("peer serialize error peer={} err={e}", peer_id_for_send);
                                break;
                            }
                        }
                    }
                });

                // Receive loop (treat as incoming).
                while let Some(frame) = ws_stream.next().await {
                    match frame {
                        Ok(TMessage::Text(txt)) => match serde_json::from_str::<UUM8DMessage>(&txt)
                        {
                            Ok(msg) => match verify_and_accept(&st, &msg).await {
                                Ok(()) => {
                                    deliver_local(&st, &msg).await;
                                    record_delivered(&st, &msg, "peer_in").await;
                                }
                                Err(err) => {
                                    warn!(
                                        "peer reject id={} from={} err={}",
                                        msg.id, msg.from_node, err
                                    );
                                    record_failed(&st, &msg, &err).await;
                                }
                            },
                            Err(e) => warn!("peer parse error peer={} err={e}", spec.peer_id),
                        },
                        Ok(TMessage::Close(_)) => break,
                        Ok(_) => {}
                        Err(e) => {
                            warn!("peer ws error peer={} err={e}", spec.peer_id);
                            break;
                        }
                    }
                }

                st.peers.write().await.remove(&spec.peer_id);
                send_task.abort();
                warn!(
                    "peer disconnected peer_id={} url={}",
                    spec.peer_id, spec.ws_url
                );
            }
            Err(e) => {
                warn!(
                    "peer dial failed peer_id={} url={} err={e}",
                    spec.peer_id, spec.ws_url
                );
            }
        }

        tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
        backoff_ms = (backoff_ms * 2).min(10_000);
    }
}

async fn verify_and_accept(st: &AppState, msg: &UUM8DMessage) -> std::result::Result<(), String> {
    if let Some(end) = msg.uum8d_payload.delivery_window_end_ms {
        if now_ms() > end {
            return Err("expired".to_string());
        }
    }

    if !msg.constitutional_proof.approved {
        return Err("constitutional_not_approved".to_string());
    }

    let computed: Blake3Hash = blake3::hash(&msg.uum8d_payload.content_bytes);
    if computed.to_hex().to_string() != msg.uum8d_payload.payload_hash_hex {
        return Err("payload_hash_mismatch".to_string());
    }

    verify_signature(msg).map_err(|e| format!("signature_invalid: {e}"))?;

    if msg.to_node != st.node_id
        && !msg
            .uum8d_payload
            .recipients
            .iter()
            .any(|r| r == &st.node_id)
    {
        return Err("not_for_this_node".to_string());
    }

    Ok(())
}

async fn deliver_local(_st: &AppState, msg: &UUM8DMessage) {
    match zstd::decode_all(msg.uum8d_payload.content_bytes.as_slice()) {
        Ok(raw) => match serde_json::from_slice::<serde_json::Value>(&raw) {
            Ok(val) => info!(
                "DELIVER local id={} from={} body={}",
                msg.id, msg.from_node, val
            ),
            Err(_) => info!(
                "DELIVER local id={} from={} bytes={}",
                msg.id,
                msg.from_node,
                raw.len()
            ),
        },
        Err(e) => warn!("deliver decode failed id={} err={e}", msg.id),
    }
}

async fn sign(
    st: &AppState,
    id: &str,
    payload: &UUM8DPayload,
) -> std::result::Result<(String, String), String> {
    let sk = st.signing_key.lock().await;
    let to_sign = format!("{id}:{}", payload.payload_hash_hex);
    let sig: Signature = sk.sign(to_sign.as_bytes());
    Ok((
        hex::encode(sig.to_bytes()),
        hex::encode(st.verifying_key.to_bytes()),
    ))
}

fn verify_signature(msg: &UUM8DMessage) -> std::result::Result<(), &'static str> {
    let pk_bytes = hex::decode(&msg.pubkey_hex).map_err(|_| "bad_pubkey_hex")?;
    let pk_arr: [u8; 32] = pk_bytes.try_into().map_err(|_| "bad_pubkey_len")?;
    let vk = VerifyingKey::from_bytes(&pk_arr).map_err(|_| "bad_pubkey")?;

    let sig_bytes = hex::decode(&msg.signature_hex).map_err(|_| "bad_sig_hex")?;
    let sig_arr: [u8; 64] = sig_bytes.try_into().map_err(|_| "bad_sig_len")?;
    let sig = Signature::from_bytes(&sig_arr);

    let to_verify = format!("{}:{}", msg.id, msg.uum8d_payload.payload_hash_hex);
    vk.verify_strict(to_verify.as_bytes(), &sig)
        .map_err(|_| "verify_failed")?;
    Ok(())
}

async fn store_pending(st: &AppState, msg: &UUM8DMessage) -> std::result::Result<(), String> {
    let doc = serde_json::to_value(msg).map_err(|e| e.to_string())?;
    let aql = AqlQuery::builder()
        .query("INSERT @doc INTO messages_pending")
        .bind_var("doc", doc)
        .build();
    st.db
        .aql_query::<serde_json::Value>(aql)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

async fn fetch_pending(
    st: &AppState,
    node_id: &str,
) -> std::result::Result<Vec<UUM8DMessage>, String> {
    let aql = AqlQuery::builder()
        .query(
            r#"
            FOR msg IN messages_pending
              FILTER msg.to_node == @node
              SORT msg.priority ASC, msg.timestamp_ms ASC
              LIMIT 100
              RETURN msg
        "#,
        )
        .bind_var("node", node_id)
        .build();
    st.db
        .aql_query::<UUM8DMessage>(aql)
        .await
        .map_err(|e| e.to_string())
}

async fn mark_pending_delivered(st: &AppState, id: &str) {
    let aql = AqlQuery::builder()
        .query(
            r#"
            LET doc = FIRST(FOR m IN messages_pending FILTER m.id == @id RETURN m)
            FILTER doc != null
            INSERT MERGE(doc, {delivered_via: "arango", delivered_ms: DATE_NOW()}) INTO messages_delivered
            REMOVE doc._key IN messages_pending
        "#,
        )
        .bind_var("id", id)
        .build();
    let _ = st.db.aql_query::<serde_json::Value>(aql).await;
}

async fn mark_pending_failed(st: &AppState, id: &str, reason: &str) {
    let aql = AqlQuery::builder()
        .query(
            r#"
            LET doc = FIRST(FOR m IN messages_pending FILTER m.id == @id RETURN m)
            FILTER doc != null
            INSERT MERGE(doc, {failed_reason: @reason, failed_ms: DATE_NOW()}) INTO messages_failed
            REMOVE doc._key IN messages_pending
        "#,
        )
        .bind_var("id", id)
        .bind_var("reason", reason)
        .build();
    let _ = st.db.aql_query::<serde_json::Value>(aql).await;
}

async fn record_delivered(st: &AppState, msg: &UUM8DMessage, via: &str) {
    let doc = serde_json::json!({
        "id": msg.id,
        "from_node": msg.from_node,
        "to_node": msg.to_node,
        "via": via,
        "ts_ms": now_ms(),
        "priority": msg.priority as u8,
    });
    let aql = AqlQuery::builder()
        .query("INSERT @doc INTO messages_delivered")
        .bind_var("doc", doc)
        .build();
    let _ = st.db.aql_query::<serde_json::Value>(aql).await;
}

async fn record_failed(st: &AppState, msg: &UUM8DMessage, reason: &str) {
    let doc = serde_json::json!({
        "id": msg.id,
        "from_node": msg.from_node,
        "to_node": msg.to_node,
        "reason": reason,
        "ts_ms": now_ms(),
        "priority": msg.priority as u8,
    });
    let aql = AqlQuery::builder()
        .query("INSERT @doc INTO messages_failed")
        .bind_var("doc", doc)
        .build();
    let _ = st.db.aql_query::<serde_json::Value>(aql).await;
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

fn priority_to_energy(p: MessagePriority) -> f32 {
    match p {
        MessagePriority::Critical => 1.0,
        MessagePriority::High => 0.8,
        MessagePriority::Normal => 0.5,
        MessagePriority::Low => 0.2,
    }
}

fn compute_routing_vector(to_node: &str) -> [f32; 8] {
    let h = blake3::hash(to_node.as_bytes());
    let b = h.as_bytes();
    [
        b[0] as f32 / 255.0,
        b[1] as f32 / 255.0,
        b[2] as f32 / 255.0,
        b[3] as f32 / 255.0,
        b[4] as f32 / 255.0,
        b[5] as f32 / 255.0,
        b[6] as f32 / 255.0,
        b[7] as f32 / 255.0,
    ]
}

fn constitutional_check(validator_node: &str, payload: &UUM8DPayload) -> ConstitutionalProof {
    let justice = if payload.energy_level <= 1.0 {
        1.0
    } else {
        0.0
    };
    let honesty = 1.0;
    let temperance = (payload.compression_ratio.min(10.0) / 10.0).clamp(0.0, 1.0);
    let prudence = (payload.max_retries as f32 / 10.0).clamp(0.0, 1.0);
    let approved = justice > 0.5 && temperance > 0.1 && prudence > 0.1;

    ConstitutionalProof {
        validator_node: validator_node.to_string(),
        validation_timestamp_ms: now_ms(),
        virtue_scores: [justice, honesty, temperance, prudence],
        approved,
        proof_signature: "".to_string(),
    }
}

async fn ensure_collection(db: &Database<ReqwestClient>, name: &str) -> Result<()> {
    // arangors returns error if exists; treat that as ok.
    match db.create_collection(name).await {
        Ok(_) => Ok(()),
        Err(e) => {
            let s = e.to_string();
            if s.contains("duplicate name") || s.contains("already exists") {
                Ok(())
            } else {
                Err(anyhow!(s))
            }
        }
    }
}

async fn init_arango(db: &Database<ReqwestClient>) -> Result<()> {
    ensure_collection(db, "messages_pending")
        .await
        .context("create messages_pending")?;
    ensure_collection(db, "messages_delivered")
        .await
        .context("create messages_delivered")?;
    ensure_collection(db, "messages_failed")
        .await
        .context("create messages_failed")?;
    Ok(())
}

fn load_or_generate_signing_key() -> Result<SigningKey> {
    // KEYPAIR_SEED_PATH: file containing 32-byte seed (raw). If present, load; else generate.
    // This keeps startup deterministic without requiring SaaS or external KMS.
    let path = std::env::var("KEYPAIR_SEED_PATH")
        .ok()
        .filter(|s| !s.trim().is_empty());
    if let Some(p) = path {
        let pb = std::path::PathBuf::from(p);
        if pb.exists() {
            let bytes = std::fs::read(&pb)
                .with_context(|| format!("read KEYPAIR_SEED_PATH {}", pb.display()))?;
            let seed: [u8; 32] = bytes
                .get(0..32)
                .ok_or_else(|| anyhow!("KEYPAIR_SEED_PATH must contain at least 32 bytes"))?
                .try_into()
                .map_err(|_| anyhow!("KEYPAIR_SEED_PATH seed slice invalid"))?;
            return Ok(SigningKey::from_bytes(&seed));
        }
        let mut csprng = OsRng;
        let sk = SigningKey::generate(&mut csprng);
        std::fs::write(&pb, sk.to_bytes())
            .with_context(|| format!("write KEYPAIR_SEED_PATH {}", pb.display()))?;
        return Ok(sk);
    }

    let mut csprng = OsRng;
    Ok(SigningKey::generate(&mut csprng))
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_target(false)
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let node_id = std::env::var("NODE_ID").unwrap_or_else(|_| "node-1".to_string());
    let bind_addr: SocketAddr = std::env::var("BIND_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:9001".to_string())
        .parse()
        .context("bad BIND_ADDR")?;

    let arango_url =
        std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://127.0.0.1:8529".to_string());
    let arango_user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
    let arango_pass = std::env::var("ARANGO_PASS").unwrap_or_else(|_| "password".to_string());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "uum8d_comms".to_string());

    let conn = Connection::establish_basic_auth(&arango_url, &arango_user, &arango_pass)
        .await
        .with_context(|| format!("arango connect failed url={arango_url}"))?;
    let db = conn
        .db(&arango_db)
        .await
        .with_context(|| format!("db open failed db={arango_db}"))?;
    init_arango(&db).await.context("init arango collections")?;
    let db = Arc::new(db);

    let signing_key = load_or_generate_signing_key().context("load/generate signing key")?;
    let verifying_key = signing_key.verifying_key();

    let st = AppState {
        node_id: node_id.clone(),
        db,
        signing_key: Arc::new(Mutex::new(signing_key)),
        verifying_key,
        peers: Arc::new(RwLock::new(HashMap::new())),
    };

    // Optional: dial-out peer mesh via PEER_ENDPOINTS.
    if let Ok(peers_env) = std::env::var("PEER_ENDPOINTS") {
        let specs = parse_peer_endpoints(&peers_env);
        if !specs.is_empty() {
            info!("peer mesh enabled peers={}", specs.len());
            for spec in specs {
                tokio::spawn(peer_connector_loop(st.clone(), spec));
            }
        }
    }

    tokio::spawn(poller_loop(st.clone()));

    let app = Router::new()
        .route("/health", get(health))
        .route("/ws", get(ws_upgrade))
        .route("/send", post(send_message))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(st);

    info!("uum8d_broker node_id={node_id} listening on {bind_addr}");
    let listener = tokio::net::TcpListener::bind(bind_addr)
        .await
        .context("bind")?;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .map_err(|e| anyhow!("server error: {e}"))
}
