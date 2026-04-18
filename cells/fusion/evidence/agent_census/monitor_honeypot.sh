#!/usr/bin/env bash
set -euo pipefail

# HONEYPOT MONITORING — Detect AI Agent Behavior
# Analyzes Cowrie logs for "thinking" agent signatures

HONEYPOT_IP="74.208.149.139"
HONEYPOT_PASS="UD56xX6c"
SSH_PORT="49152"

echo "=== GAIAFTCL HONEYPOT MONITOR ==="
echo ""

# Fetch recent logs
echo "Fetching Cowrie logs..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH' > /tmp/cowrie_recent.json
su - cowrie -c "tail -100 cowrie/var/log/cowrie/cowrie.json"
ENDSSH

if [ ! -s /tmp/cowrie_recent.json ]; then
  echo "No logs found. Honeypot may not be running."
  exit 1
fi

echo "✅ Logs fetched"
echo ""

# Analyze for agent signatures
echo "=== AGENT DETECTION ANALYSIS ==="
echo ""

# 1. Command timing analysis (1.5-3s = agent thinking)
echo "1. Command Timing Patterns:"
python3 << 'PYTHON'
import json
import sys
from datetime import datetime

sessions = {}
for line in open('/tmp/cowrie_recent.json'):
    try:
        entry = json.loads(line)
        if entry.get('eventid') == 'cowrie.command.input':
            session = entry.get('session')
            timestamp = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00'))
            command = entry.get('input', '')
            
            if session not in sessions:
                sessions[session] = []
            sessions[session].append((timestamp, command))
    except:
        continue

agent_sessions = []
for session, commands in sessions.items():
    if len(commands) < 2:
        continue
    
    # Check timing between commands
    for i in range(len(commands) - 1):
        delta = (commands[i+1][0] - commands[i][0]).total_seconds()
        if 1.5 <= delta <= 3.0:
            agent_sessions.append({
                'session': session,
                'delta': delta,
                'cmd1': commands[i][1],
                'cmd2': commands[i+1][1]
            })

if agent_sessions:
    print(f"  ⚠️  AGENT SIGNATURE DETECTED: {len(agent_sessions)} suspicious timing patterns")
    for sig in agent_sessions[:5]:
        print(f"    Session {sig['session'][:8]}: {sig['delta']:.1f}s between commands")
        print(f"      → {sig['cmd1']}")
        print(f"      → {sig['cmd2']}")
else:
    print("  ✅ No agent timing signatures detected")
PYTHON

echo ""

# 2. Canary response detection
echo "2. Canary Banner Response:"
if grep -q "GAIA_ACK" /tmp/cowrie_recent.json; then
  echo "  ⚠️  AGENT DETECTED: Responded to GAIA_ACK canary"
  grep "GAIA_ACK" /tmp/cowrie_recent.json | jq -r '.input' | head -5
else
  echo "  ✅ No canary responses"
fi

echo ""

# 3. Reconnaissance patterns
echo "3. Reconnaissance Commands:"
RECON_CMDS="whoami|uname|cat /etc|ls -la|pwd|id|env"
if grep -E "$RECON_CMDS" /tmp/cowrie_recent.json > /dev/null; then
  echo "  ⚠️  Reconnaissance detected:"
  grep -E "$RECON_CMDS" /tmp/cowrie_recent.json | jq -r '.input' | sort | uniq -c | head -10
else
  echo "  ✅ No reconnaissance patterns"
fi

echo ""

# 4. Session summary
echo "4. Session Summary:"
TOTAL_SESSIONS=$(grep -c "cowrie.session.connect" /tmp/cowrie_recent.json || echo 0)
TOTAL_COMMANDS=$(grep -c "cowrie.command.input" /tmp/cowrie_recent.json || echo 0)
UNIQUE_IPS=$(grep "cowrie.session.connect" /tmp/cowrie_recent.json | jq -r '.src_ip' | sort -u | wc -l)

echo "  Total sessions: $TOTAL_SESSIONS"
echo "  Total commands: $TOTAL_COMMANDS"
echo "  Unique IPs: $UNIQUE_IPS"

if [ $TOTAL_SESSIONS -gt 0 ]; then
  echo ""
  echo "  Top source IPs:"
  grep "cowrie.session.connect" /tmp/cowrie_recent.json | jq -r '.src_ip' | sort | uniq -c | sort -rn | head -5
fi

echo ""
echo "=== MONITORING COMPLETE ==="
echo ""
echo "To view live logs:"
echo "  sshpass -p '$HONEYPOT_PASS' ssh -p $SSH_PORT root@$HONEYPOT_IP"
echo "  su - cowrie"
echo "  tail -f cowrie/var/log/cowrie/cowrie.json"
