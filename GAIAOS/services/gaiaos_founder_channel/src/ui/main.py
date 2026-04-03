import streamlit as st
import requests
import json
from datetime import datetime
import uuid

BACKEND_URL = "http://localhost:8006"

# Chat-First Layout
st.set_page_config(page_title="GAIAOS Founder Channel", layout="wide", initial_sidebar_state="collapsed")

# Custom CSS for sticky chat input and cleaner look
st.markdown("""
<style>
    .stChatFloatingInputContainer {
        bottom: 20px;
    }
    .main .block-container {
        padding-top: 2rem;
        padding-bottom: 5rem;
    }
    .stChatMessage {
        border-radius: 10px;
        padding: 10px;
        margin-bottom: 10px;
    }
    .metadata-box {
        font-size: 0.75rem;
        color: #888;
        margin-top: -10px;
        margin-bottom: 15px;
        padding-left: 50px;
    }
</style>
""", unsafe_allow_html=True)

# Sidebar (Collapsed by default)
with st.sidebar:
    st.header("⚙️ System Control")
    try:
        st.success("Supervisor: Online")
        if st.button("🔄 Restart GaiaOS Stack"):
            res = requests.post(f"{BACKEND_URL}/system/command", json={"type": "RESTART"})
            if res.status_code == 200: st.info("Restart command emitted.")
    except:
        st.error("Supervisor: Offline")
    
    st.markdown("---")
    st.header("🕹️ Active Games")
    if st.button("➕ New Game"):
        game_id = f"G_GAME_{uuid.uuid4().hex[:8]}"
        st.session_state.game_id = game_id
        st.session_state.messages = []
    
    try:
        threads = requests.get(f"{BACKEND_URL}/threads").json()
        for t in threads:
            label = f"Game {t['game_id'][:12]}..."
            if st.sidebar.button(label, key=t['game_id']):
                st.session_state.game_id = t['game_id']
                st.session_state.messages = requests.get(f"{BACKEND_URL}/messages/{t['game_id']}").json()
    except:
        st.sidebar.error("Backend offline.")

# Main Chat Area
if "game_id" not in st.session_state:
    st.title("🕹️ GAIAOS Founder Channel")
    st.info("Select a game from the sidebar or start a new one to begin conversation.")
else:
    # Game Header (Small/Collapsible)
    with st.expander(f"Game: {st.session_state.game_id}", expanded=False):
        st.write("Live Conversation Substrate active.")
    
    # Message Container (Occupies most of the screen)
    message_container = st.container()
    
    with message_container:
        for msg in st.session_state.get("messages", []):
            role = "user" if msg["from_role"] == "FOUNDER" else "assistant"
            with st.chat_message(role):
                if msg["kind"] == "SPEECH":
                    st.write(msg["text"])
                elif msg["kind"] == "QSTATE_PROPOSAL":
                    st.warning("⚡ TRUTH PROMOTION PROPOSAL")
                    st.json(msg["proposal"])
                    if st.button("Approve & Commit to Truth", key=f"app_{msg['move_id']}"):
                        # Logic to promote to Truth Envelope
                        truth_payload = {
                            "game_id": msg["game_id"],
                            "from_role": "FOUNDER",
                            "envelope_type": msg["proposal"]["suggested_truth_envelope_type"],
                            "claims": [{"claim": c} for c in msg["proposal"]["candidate_claims"]],
                            "evidence_refs": msg["proposal"]["required_evidence_refs"],
                            "provenance": "FOUNDER_PROMOTION",
                            "binding_effects": {"actions": ["EXECUTE_DIRECTIVE"]}
                        }
                        requests.post(f"{BACKEND_URL}/founder/truth", json=truth_payload)
                        st.rerun()
                elif msg["kind"] == "TRUTH":
                    st.success(f"✅ TRUTH ENVELOPE: {msg['envelope_type']}")
                    st.json(msg["claims"])
                    st.caption(f"Provenance: {msg['provenance']}")
            
            # Canonical Metadata
            st.markdown(f"""<div class='metadata-box'>{msg['created_at']} | {msg['kind']} | {msg['from_role']} | Move: {msg['move_id'][:8]}</div>""", unsafe_allow_html=True)

    # Sticky Input Bar (Always active)
    if prompt := st.chat_input("Message the Family..."):
        payload = {
            "game_id": st.session_state.game_id,
            "from_role": "FOUNDER",
            "text": prompt,
            "context_refs": []
        }
        res = requests.post(f"{BACKEND_URL}/founder/speech", json=payload)
        if res.status_code == 200:
            st.session_state.messages = requests.get(f"{BACKEND_URL}/messages/{st.session_state.game_id}").json()
            st.rerun()

# Automatic refresh (Polling for now, WebSocket handled in backend)
if st.button("🔄 Sync Game"):
    if "game_id" in st.session_state:
        st.session_state.messages = requests.get(f"{BACKEND_URL}/messages/{st.session_state.game_id}").json()
        st.rerun()
