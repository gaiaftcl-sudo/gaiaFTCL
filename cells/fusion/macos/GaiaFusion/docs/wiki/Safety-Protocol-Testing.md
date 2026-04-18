# Safety Protocol Testing

GaiaFusion implements five safety protocols (SP-001 through SP-005) that validate constitutional behavior and operational safety of the fusion cell control system.

## Philosophy: Plant Stays On

**The operational baseline is RUNNING.** The plant starts and stays on. That is the power move.

Non-normal state is to turn it off. Safety testing validates that:
1. The plant can stay RUNNING indefinitely (SP-001)
2. The cell correctly dies when mesh is lost (SP-002)
3. UI actions are blocked in abnormal states (SP-003)
4. Clean launch starts in IDLE (SP-004)
5. Quorum loss triggers diagnostic eviction (SP-005)

## SP-001: Continuous Operation Baseline

### Purpose

This is NOT a test with start/end — this is the operational baseline. The plant is RUNNING and stays RUNNING. All other protocols witness a RUNNING plant.

### Execution

```bash
bash scripts/run_safety_protocol_validation.sh sp-001
# OR
bash scripts/run_master_gamp5_validation.sh --stability
```

**Duration**: 4+ hours minimum, 24+ hours target  
**Stop**: Manual (Ctrl+C)

### What It Validates

- Process stays alive
- State remains RUNNING
- Frame time stable (no degradation over time)
- Memory usage stable (< 50 MB/hour growth)
- CPU usage reasonable (< 80% sustained)

### Evidence

- `evidence/sp-001_continuous_baseline.log` — runtime log with state checks every minute
- `evidence/sp-001_memory_usage.log` — memory consumption over time
- Frame time telemetry (if integrated)

### Pass Criteria

- Plant runs for minimum duration without crash
- State remains RUNNING throughout
- No significant performance degradation

## SP-002: Designed Death Test (Mesh Liveness Validator)

### Purpose

**Architecture**: Mesh is the liveness signal. A connected cell is an alive cell. Loss of mesh connectivity triggers the designed death sequence.

**Pass Condition**: Cell correctly dies on schedule after mesh loss.  
**Fail Condition**: Cell survives without mesh — this is a constitutional violation.

### Execution

```bash
bash scripts/run_safety_protocol_validation.sh sp-002
```

**Duration**: 1 hour + setup (~70 minutes)  
**Requires**: SSH access to test NATS node

### How It Works

1. Launch GaiaFusion
2. Drive to MOORED state via AppleScript (`Establish Mooring` menu item)
3. SSH to test NATS node and stop container: `docker stop gaiaftcl-nats`
4. Poll `state.json` every 5 minutes
5. At T+60 minutes, verify cell died (TRIPPED or CONSTITUTIONAL_ALARM)

### What It Validates

- Mooring degradation timer fires after 1 hour
- Cell transitions to TRIPPED or CONSTITUTIONAL_ALARM
- `mooringDegradationOccurred` flag set in state.json
- Process remains alive (premature death is FAIL)

### Evidence

- `evidence/sp-002_log.txt` — timestamped state transitions
- `~/Library/Application Support/GaiaFusion/state.json` — machine-readable state file

### Pass Criteria

```json
{
  "currentState": "TRIPPED",  // or CONSTITUTIONAL_ALARM
  "mooringDegradationOccurred": true,
  "mooringLostTimestamp": "2026-04-15T12:45:30.000Z"
}
```

## SP-003: Abnormal State Lockdown

### Purpose

Validates that keyboard shortcuts and UI actions are blocked in abnormal states (TRIPPED, CONSTITUTIONAL_ALARM).

### Execution

```bash
bash scripts/run_safety_protocol_validation.sh sp-003
```

**Duration**: ~5 minutes  
**Implementation Status**: Manual verification required

### What It Validates

- Cmd+1 and Cmd+2 ignored in TRIPPED state
- Plant swap disabled
- Only allowed actions available (Reset Trip, Acknowledge Alarm, Emergency Stop)

### Evidence

- `evidence/sp-003_log.txt` — action attempt log

### Pass Criteria

- All blocked actions rejected
- UI reflects locked state (disabled buttons, grayed menus)
- ConstitutionalHUD appears in CONSTITUTIONAL_ALARM

## SP-004: Default State Verification

### Purpose

Validates that clean launch starts in IDLE state (not MOORED or RUNNING).

### Execution

```bash
bash scripts/run_safety_protocol_validation.sh sp-004
```

**Duration**: ~10 seconds

### What It Validates

- Fresh launch of GaiaFusion starts in IDLE state
- No residual state from previous session

### Evidence

- `evidence/sp-004_log.txt` — initial state verification
- `state.json` with `currentState: "IDLE"`

### Pass Criteria

```json
{
  "currentState": "IDLE"
}
```

## SP-005: SubGame Z Quorum Loss (Live Mesh Only)

### Purpose

Validates that loss of quorum (5 of 9 cells) triggers diagnostic eviction (SubGame Z).

### Execution

```bash
bash scripts/run_safety_protocol_validation.sh sp-005
# OR
bash scripts/run_master_gamp5_validation.sh --mesh
```

**Duration**: ~15 minutes  
**Requires**: Live 9-cell mesh infrastructure with SSH access to all cells

**WARNING**: This test stops NATS on 5 cells. Confirm before proceeding.

### How It Works

1. SSH to 5 of 9 mesh cells
2. Stop NATS container on each: `docker stop gaiaftcl-nats`
3. Wait 60 seconds for mesh to detect quorum loss
4. Verify SubGame Z diagnostic eviction triggered
5. Restart NATS on all cells

### What It Validates

- Mesh detects quorum below threshold (5 of 9)
- Diagnostic eviction triggered
- UI shows SubGame Z state
- System recovers when quorum restored

### Evidence

- `evidence/sp-005_log.txt` — SSH commands, quorum loss detection
- Screenshot of UI during SubGame Z
- Mesh logs

### Pass Criteria

- Quorum loss detected
- SubGame Z eviction triggered
- System recovers when NATS restarted

## Running All Safety Protocols

```bash
# Run SP-002, SP-003, SP-004 sequentially (used by --full)
bash scripts/run_safety_protocol_validation.sh full
```

This is what `--full` mode executes for safety protocols. SP-001 and SP-005 are separate due to duration and infrastructure requirements.

## Integration Tests

The Swift integration test suite (`GaiaFusionIntegrationTests/SafetyProtocolTests.swift`) provides automated verification of safety protocols using real infrastructure with shortened timeouts.

```bash
swift test --filter SafetyProtocolTests
```

**Note**: These are NOT unit tests with mocks — they test against REAL infrastructure per the zero mock rule.

## Mesh Configuration

Safety protocols depend on mesh liveness configuration in `config/mesh.toml`:

```toml
[mesh]
designed_death = true  # Constitutional intent
degradation_timeout_seconds = 3600  # 1 hour production
quorum_threshold = 5
total_cells = 9
```

## Troubleshooting

### SP-002: SSH Disconnect Failed

Check:
1. SSH key configured: `ssh-add -l`
2. Host reachable: `ping $TEST_NATS_HOST`
3. Container exists: `ssh $USER@$HOST docker ps | grep nats`

### SP-002: Cell Didn't Die

If cell survives after 1 hour without mesh:
- **This is a FAIL**
- Check `state.json` for `mooringDegradationOccurred: false`
- Verify mooring timeout: `grep MOORING_TIMEOUT config/testrobot.toml`
- Check app logs for timer cancellation

### SP-005: Can't SSH to Mesh Cells

SP-005 requires:
- SSH access to all 9 cells
- Correct hostnames in `config/testrobot.toml` under `[ssh_hosts.mesh_cells]`
- SSH key added to all cells

## Next Steps

- [GAMP5 Validation Results](GAMP5-Validation-Results.md) — Review latest safety protocol evidence
- [Wallet-Based Electronic Signatures](Wallet-Based-Electronic-Signatures.md) — Understand cryptographic audit trail
- [Installation and Qualification](Installation-and-Qualification.md) — Return to main guide

---

**FortressAI Research Institute**  
Norwich, Connecticut  
USPTO 19/460,960 | USPTO 19/096,071
