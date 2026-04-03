#!/usr/bin/env python3
"""
GAIAOS EXAM EVIDENCE API
========================
Serves IQ/OQ/PQ validation results and MP4 evidence to users.
Allows querying exam history and viewing proof of mastery.
"""

from flask import Flask, jsonify, send_file, request, render_template_string
from pathlib import Path
import json
import os
from datetime import datetime

app = Flask(__name__)

GAIAOS_ROOT = Path("/Users/richardgillespie/Documents/FoT8D/GAIAOS")
EVIDENCE_BASE = GAIAOS_ROOT / "evidence-pack"

DOMAINS = [
    "medicine", "legal", "chemistry", "finance", "engineering",
    "code", "math", "protein", "galaxy", "vision", 
    "world_models", "fara", "generalreasoning"
]

# ═══════════════════════════════════════════════════════════════════════════════
# API ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/")
def index():
    """Dashboard showing all domain statuses"""
    return render_template_string(DASHBOARD_HTML, domains=DOMAINS)

@app.route("/api/status")
def api_status():
    """Overall system status"""
    status = {
        "system": "GAIAOS IQ/OQ/PQ Validation",
        "status": "ACTIVE",
        "domains": len(DOMAINS),
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }
    
    total_qa = 0
    total_correct = 0
    
    for domain in DOMAINS:
        runs_dir = EVIDENCE_BASE / "runs" / domain
        for jsonl in runs_dir.glob("*.jsonl"):
            with open(jsonl) as f:
                for line in f:
                    total_qa += 1
                    if '"correct"' in line:
                        total_correct += 1
    
    status["total_qa"] = total_qa
    status["total_correct"] = total_correct
    status["accuracy"] = round(100 * total_correct / max(total_qa, 1), 1)
    
    return jsonify(status)

@app.route("/api/domains")
def api_domains():
    """List all domains with stats"""
    results = []
    
    for domain in DOMAINS:
        stats = get_domain_stats(domain)
        results.append(stats)
    
    return jsonify({"domains": results})

@app.route("/api/domain/<domain>")
def api_domain(domain):
    """Get detailed stats for a domain"""
    if domain not in DOMAINS:
        return jsonify({"error": "Invalid domain"}), 404
    
    stats = get_domain_stats(domain)
    
    # Get recent runs
    runs_dir = EVIDENCE_BASE / "runs" / domain
    runs = []
    for jsonl in sorted(runs_dir.glob("*.jsonl"), reverse=True)[:10]:
        run_stats = get_run_stats(jsonl)
        runs.append(run_stats)
    
    stats["recent_runs"] = runs
    
    return jsonify(stats)

@app.route("/api/domain/<domain>/runs")
def api_domain_runs(domain):
    """List all runs for a domain"""
    if domain not in DOMAINS:
        return jsonify({"error": "Invalid domain"}), 404
    
    runs_dir = EVIDENCE_BASE / "runs" / domain
    runs = []
    
    for jsonl in sorted(runs_dir.glob("*.jsonl"), reverse=True):
        run_stats = get_run_stats(jsonl)
        runs.append(run_stats)
    
    return jsonify({"domain": domain, "runs": runs})

@app.route("/api/run/<domain>/<run_id>")
def api_run_detail(domain, run_id):
    """Get detailed results for a specific run"""
    if domain not in DOMAINS:
        return jsonify({"error": "Invalid domain"}), 404
    
    jsonl_path = EVIDENCE_BASE / "runs" / domain / f"{run_id}.jsonl"
    if not jsonl_path.exists():
        return jsonify({"error": "Run not found"}), 404
    
    questions = []
    with open(jsonl_path) as f:
        for i, line in enumerate(f):
            try:
                q = json.loads(line)
                questions.append({
                    "index": i + 1,
                    "subdomain": q.get("subdomain", ""),
                    "question": q.get("guardian_prompt", "")[:200],
                    "answer": q.get("student_answer", "")[:300],
                    "verdict": q.get("franklin_verdict", ""),
                    "truth_score": q.get("truth_score", 0),
                    "virtue_score": q.get("virtue_score", 0)
                })
            except:
                pass
    
    return jsonify({
        "domain": domain,
        "run_id": run_id,
        "total": len(questions),
        "correct": sum(1 for q in questions if q["verdict"] == "correct"),
        "questions": questions
    })

@app.route("/api/videos/<domain>")
def api_videos(domain):
    """List available videos for a domain"""
    if domain not in DOMAINS:
        return jsonify({"error": "Invalid domain"}), 404
    
    videos_dir = EVIDENCE_BASE / "videos" / domain
    videos = []
    
    for mp4 in sorted(videos_dir.glob("*.mp4"), reverse=True):
        size_mb = mp4.stat().st_size / (1024 * 1024)
        videos.append({
            "filename": mp4.name,
            "size_mb": round(size_mb, 1),
            "url": f"/video/{domain}/{mp4.name}"
        })
    
    return jsonify({"domain": domain, "videos": videos})

@app.route("/video/<domain>/<filename>")
def serve_video(domain, filename):
    """Serve an MP4 video file"""
    if domain not in DOMAINS:
        return jsonify({"error": "Invalid domain"}), 404
    
    video_path = EVIDENCE_BASE / "videos" / domain / filename
    if not video_path.exists():
        return jsonify({"error": "Video not found"}), 404
    
    return send_file(video_path, mimetype="video/mp4")

@app.route("/api/akg/manifest")
def api_akg_manifest():
    """Get AKG manifest of all validated runs"""
    manifest_path = EVIDENCE_BASE / "akg_manifest.jsonl"
    entries = []
    
    if manifest_path.exists():
        with open(manifest_path) as f:
            for line in f:
                try:
                    entries.append(json.loads(line))
                except:
                    pass
    
    return jsonify({
        "total_entries": len(entries),
        "entries": entries[-100:]  # Last 100 entries
    })

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def get_domain_stats(domain):
    """Get statistics for a domain"""
    runs_dir = EVIDENCE_BASE / "runs" / domain
    videos_dir = EVIDENCE_BASE / "videos" / domain
    
    total_qa = 0
    total_correct = 0
    run_count = 0
    
    for jsonl in runs_dir.glob("*.jsonl"):
        run_count += 1
        with open(jsonl) as f:
            for line in f:
                total_qa += 1
                if '"correct"' in line:
                    total_correct += 1
    
    video_count = len(list(videos_dir.glob("*.mp4"))) if videos_dir.exists() else 0
    
    return {
        "domain": domain,
        "total_qa": total_qa,
        "correct": total_correct,
        "accuracy": round(100 * total_correct / max(total_qa, 1), 1),
        "runs": run_count,
        "videos": video_count
    }

def get_run_stats(jsonl_path):
    """Get stats for a single run"""
    total = 0
    correct = 0
    
    with open(jsonl_path) as f:
        for line in f:
            total += 1
            if '"correct"' in line:
                correct += 1
    
    return {
        "run_id": jsonl_path.stem,
        "total": total,
        "correct": correct,
        "accuracy": round(100 * correct / max(total, 1), 1)
    }

# ═══════════════════════════════════════════════════════════════════════════════
# DASHBOARD HTML
# ═══════════════════════════════════════════════════════════════════════════════

DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>GaiaOS IQ/OQ/PQ Validation Dashboard</title>
    <style>
        body { 
            font-family: 'SF Mono', 'Monaco', monospace; 
            background: #0a0a0a; 
            color: #00ff88; 
            padding: 20px;
            margin: 0;
        }
        h1 { color: #00ff88; border-bottom: 2px solid #00ff88; padding-bottom: 10px; }
        .domain-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .domain-card { 
            background: #111; 
            border: 1px solid #00ff88; 
            padding: 15px; 
            border-radius: 8px;
        }
        .domain-name { font-size: 1.2em; color: #fff; margin-bottom: 10px; }
        .stat { margin: 5px 0; }
        .accuracy { font-size: 1.5em; color: #00ff88; }
        .accuracy.high { color: #00ff88; }
        .accuracy.med { color: #ffaa00; }
        .accuracy.low { color: #ff4444; }
        a { color: #00aaff; }
        .api-links { margin-top: 30px; padding: 20px; background: #111; border-radius: 8px; }
        .api-links a { display: block; margin: 5px 0; }
    </style>
</head>
<body>
    <h1>🧠 GaiaOS IQ/OQ/PQ Validation Dashboard</h1>
    
    <div id="status">Loading...</div>
    
    <h2>Domain Performance</h2>
    <div class="domain-grid" id="domains">Loading domains...</div>
    
    <div class="api-links">
        <h3>API Endpoints</h3>
        <a href="/api/status">/api/status - System overview</a>
        <a href="/api/domains">/api/domains - All domain stats</a>
        <a href="/api/akg/manifest">/api/akg/manifest - AKG validation manifest</a>
    </div>
    
    <script>
        async function loadData() {
            const status = await fetch('/api/status').then(r => r.json());
            document.getElementById('status').innerHTML = `
                <p>Total QA: <strong>${status.total_qa}</strong> | 
                Correct: <strong>${status.total_correct}</strong> | 
                Accuracy: <strong>${status.accuracy}%</strong></p>
            `;
            
            const domains = await fetch('/api/domains').then(r => r.json());
            document.getElementById('domains').innerHTML = domains.domains.map(d => `
                <div class="domain-card">
                    <div class="domain-name">${d.domain.toUpperCase()}</div>
                    <div class="accuracy ${d.accuracy >= 90 ? 'high' : d.accuracy >= 70 ? 'med' : 'low'}">${d.accuracy}%</div>
                    <div class="stat">QA: ${d.correct}/${d.total_qa}</div>
                    <div class="stat">Runs: ${d.runs} | Videos: ${d.videos}</div>
                    <a href="/api/domain/${d.domain}">View Details</a> | 
                    <a href="/api/videos/${d.domain}">Videos</a>
                </div>
            `).join('');
        }
        loadData();
        setInterval(loadData, 30000);
    </script>
</body>
</html>
"""

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("═══════════════════════════════════════════════════════════════════════════════")
    print("  GAIAOS EXAM EVIDENCE API")
    print("  http://localhost:8850")
    print("═══════════════════════════════════════════════════════════════════════════════")
    app.run(host="0.0.0.0", port=8850, debug=False)

