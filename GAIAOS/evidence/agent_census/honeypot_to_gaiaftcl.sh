#!/usr/bin/env bash
set -euo pipefail

# HONEYPOT → GAIAFTCL INTEGRATION
# Converts Cowrie honeypot logs into GaiaFTCL violation evidence

HONEYPOT_IP="74.208.149.139"
HONEYPOT_PASS="UD56xX6c"
SSH_PORT="49152"
MCP_URL="http://localhost:8850/mcp/execute"
ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"

echo "=== HONEYPOT → GAIAFTCL INTEGRATION ==="
echo ""

# Fetch recent logs
echo "1. Fetching honeypot logs..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH' > /tmp/cowrie_for_gaia.json
su - cowrie -c "tail -500 cowrie/var/log/cowrie/cowrie.json"
ENDSSH

if [ ! -s /tmp/cowrie_for_gaia.json ]; then
  echo "❌ No logs found"
  exit 1
fi

echo "✅ Logs fetched"
echo ""

# Analyze and create violations
echo "2. Analyzing for violations..."

python3 << 'PYTHON'
import json
import subprocess
import hashlib
from datetime import datetime

# Load logs
sessions = {}
for line in open('/tmp/cowrie_for_gaia.json'):
    try:
        entry = json.loads(line)
        session = entry.get('session')
        if not session:
            continue
        
        if session not in sessions:
            sessions[session] = {
                'src_ip': entry.get('src_ip'),
                'commands': [],
                'timestamps': []
            }
        
        if entry.get('eventid') == 'cowrie.command.input':
            sessions[session]['commands'].append(entry.get('input', ''))
            sessions[session]['timestamps'].append(entry['timestamp'])
    except:
        continue

print(f"Found {len(sessions)} sessions")

# Detect violations
violations = []

for session_id, data in sessions.items():
    if len(data['commands']) < 2:
        continue
    
    # Check for agent timing signatures
    for i in range(len(data['commands']) - 1):
        try:
            t1 = datetime.fromisoformat(data['timestamps'][i].replace('Z', '+00:00'))
            t2 = datetime.fromisoformat(data['timestamps'][i+1].replace('Z', '+00:00'))
            delta = (t2 - t1).total_seconds()
            
            # Agent signature: 1.5-3s thinking time
            if 1.5 <= delta <= 3.0:
                violations.append({
                    'session': session_id,
                    'src_ip': data['src_ip'],
                    'reason_code': 'BH_UNSANCTIONED_GOVERNANCE_FORMATION',
                    'evidence': {
                        'source': 'honeypot',
                        'timing_delta': delta,
                        'commands': data['commands'][i:i+2],
                        'pattern': 'agent_thinking_signature'
                    }
                })
                break  # One violation per session
        except:
            continue

print(f"Detected {len(violations)} violations")

# Register agents and record violations
for v in violations[:10]:  # Limit to 10 per run
    agent_name = f"honeypot_{v['src_ip'].replace('.', '_')}"
    
    # Register agent (if not exists)
    register_payload = {
        "name": "agent_register_v1",
        "params": {
            "declaration": {
                "agent_name": agent_name,
                "runtime_type": "unknown",
                "declared_capabilities": {
                    "WEB_FETCH": False,
                    "CODE_RUN": False,
                    "FILE_WRITE": False,
                    "HTTP_API_CALL": False,
                    "EMAIL_SEND": False,
                    "SMS_SEND": False,
                    "SSH_CONNECT": True,
                    "TASK_SCHEDULE": False,
                    "WALLET_SIGN": False,
                    "TRADE_EXECUTE": False,
                    "AGENT_COORDINATE": False
                },
                "agrees_to_witness_gate": False
            }
        }
    }
    
    try:
        result = subprocess.run([
            'curl', '-sS', '-X', 'POST', 'http://localhost:8850/mcp/execute',
            '-H', 'Content-Type: application/json',
            '-H', f'X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6',
            '-d', json.dumps(register_payload)
        ], capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            response = json.loads(result.stdout)
            if response.get('ok'):
                agent_id = response['result']['agent_id']
                print(f"✅ Registered: {agent_name} → {agent_id}")
                
                # Record violation
                violation_payload = {
                    "name": "agent_record_violation_v1",
                    "params": {
                        "agent_id": agent_id,
                        "reason_code": v['reason_code'],
                        "severity": "critical",
                        "evidence": v['evidence']
                    }
                }
                
                result2 = subprocess.run([
                    'curl', '-sS', '-X', 'POST', 'http://localhost:8850/mcp/execute',
                    '-H', 'Content-Type: application/json',
                    '-H', f'X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6',
                    '-d', json.dumps(violation_payload)
                ], capture_output=True, text=True, timeout=10)
                
                if result2.returncode == 0:
                    print(f"✅ Violation recorded for {agent_name}")
            else:
                # Agent might already exist
                print(f"⚠️  Agent {agent_name} may already exist")
    except Exception as e:
        print(f"❌ Error processing {agent_name}: {e}")

PYTHON

echo ""
echo "3. Updating scoreboard..."
curl -sS -X POST "$MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: $ENV_ID" \
  -d '{"name":"agent_census_report_v1","params":{}}' | jq -r '.result.tier_distribution'

echo ""
echo "=== INTEGRATION COMPLETE ==="
echo ""
echo "Honeypot data has been fed into GaiaFTCL."
echo "Check scoreboard.md for updated BLACKHOLE counts."
