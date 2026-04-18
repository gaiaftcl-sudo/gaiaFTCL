# Installation and Qualification Guide

Welcome to the GaiaFusion GAMP 5 Validation System. This guide covers installation, initial qualification (IQ), and basic operational verification.

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later with command line tools
- Python 3.9+
- Rust toolchain (for config CLI)
- 16 GB RAM minimum
- Access to NATS mesh (for full validation)

## Quick Start

```bash
# Clone repository
cd macos/GaiaFusion

# Run full validation suite (IQ → OQ → RT → Safety → PQ)
bash scripts/run_master_gamp5_validation.sh --full
```

## Installation Steps

### 1. Install Dependencies

```bash
# Install Xcode command line tools (if not already installed)
xcode-select --install

# Install Python dependencies (if needed)
python3 -m pip install --upgrade pip

# Build Rust config CLI
cd tools/gaiafusion-config-cli
cargo build --release
cd ../..
```

### 2. Configure Validation Environment

Edit `config/testrobot.toml` to match your environment:

```toml
[ssh_hosts]
test_nats_host = "your-test-nats-node.local"
test_nats_user = "your-ssh-user"
```

### 3. Run Installation Qualification (IQ)

```bash
# Mac Qualification is now Swift-only to prevent kernel deadlocks
cd macos/CleanCloneTest
swift run
```

This verifies:
- App bundle builds successfully
- All required files are present
- Metal shaders compile
- Configuration files are valid

Evidence generated: `evidence/iq/macfusion_iq_receipt.json`, `evidence/iq/machealth_iq_receipt.json`

### 4. Run Software-in-the-Loop (SIL) OQ

For the MacHealth cell, GAMP 5 Category 5 requires a virtualized RF edge to safely test safety interlocks.

```bash
cd macos/SILOQRunner
swift run
```

This executes:
- ZMQ Wire Format validation
- Telemetry Schema Binding
- Games Narrative Report generation

## Validation Modes

### Full Validation (`--full`)

Runs the complete validation suite sequentially:
- **IQ**: Installation Qualification
- **OQ**: Operational Qualification (build integrity)
- **RT**: Runtime Verification (7 visual checks)
- **Safety**: SP-002 (designed death), SP-003 (lockdown), SP-004 (default state)
- **PQ**: Performance Qualification
- **Evidence**: HTML report generation

**Duration**: 2-3 hours  
**Use case**: Before CERN handoff, after major changes

```bash
bash scripts/run_master_gamp5_validation.sh --full
```

### Continuous Baseline (`--stability`)

Runs SP-001: Continuous Operation Baseline
- Plant stays RUNNING
- Monitors frame time, memory, CPU
- No automatic end — stop with Ctrl+C

**Duration**: 4+ hours minimum (24+ hours target)  
**Use case**: Production validation, long-term stability verification

```bash
bash scripts/run_master_gamp5_validation.sh --stability
```

### Live Mesh Test (`--mesh`)

Runs SP-005: SubGame Z Quorum Loss
- Requires live 9-cell mesh infrastructure
- Stops NATS on 5 cells to trigger quorum loss
- Verifies diagnostic eviction

**Duration**: ~15 minutes  
**Use case**: Manual execution before CERN handoff, requires SSH access to all cells

```bash
bash scripts/run_master_gamp5_validation.sh --mesh
```

## Understanding Visual Confirmations

The TestRobot system includes 7 runtime verification checks (RT-001 through RT-007) that require visual confirmation:

1. **RT-001**: Launch without crash
2. **RT-002**: Metal torus centered in viewport
3. **RT-003**: Next.js dashboard visible on right side
4. **RT-004**: Cmd+1 and Cmd+2 keyboard shortcuts work
5. **RT-005**: Shortcuts locked in TRIPPED state
6. **RT-006**: ConstitutionalHUD appears in CONSTITUTIONAL_ALARM
7. **RT-007**: Plasma particles only visible in RUNNING state

Each check:
- Captures a screenshot automatically
- Opens the screenshot in Quick Look
- Presents a dialog with pass criteria
- Records your pass/fail decision

## Evidence Review

After validation completes:

```bash
# View HTML evidence report
open evidence/reports/gamp5_validation_report.html

# Review receipts
ls -l evidence/receipts/

# Check screenshots
open evidence/screenshots/
```

## Troubleshooting

### Build Fails

```bash
# Clean build
rm -rf .build
swift build --configuration release
```

### Config CLI Not Found

```bash
# Rebuild config CLI
cd tools/gaiafusion-config-cli
cargo clean
cargo build --release
cd ../..
```

### NATS Connection Failed

Check that:
1. Test NATS host is reachable: `ping $TEST_NATS_HOST`
2. SSH access works: `ssh $TEST_NATS_USER@$TEST_NATS_HOST`
3. NATS container exists: `ssh $TEST_NATS_USER@$TEST_NATS_HOST docker ps`

### State File Not Found

```bash
# Check app support directory
ls -l ~/Library/Application\ Support/GaiaFusion/
```

If missing, the app may not have launched successfully. Check Console.app for errors.

## Next Steps

- [Safety Protocol Testing](Safety-Protocol-Testing.md) — Deep dive into SP-001 through SP-005
- [GAMP5 Validation Results](GAMP5-Validation-Results.md) — Review latest validation evidence
- [Wallet-Based Electronic Signatures](Wallet-Based-Electronic-Signatures.md) — Understand cryptographic audit trail

## Support

For questions or issues:
- GitHub Issues: https://github.com/gaiaftcl-sudo/gaiaFTCL/issues
- Email: research@fortressai.com

---

**FortressAI Research Institute**  
Norwich, Connecticut  
USPTO 19/460,960 | USPTO 19/096,071
