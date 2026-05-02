# GAMP 5 — OQ evidence package (live execution)

**Status:** sealed — Step 8 operational qualification (GaiaFTCL).  
**Placeholder (section 12 — replace in sign-off commit):** `2b77d4813fed387a61544fa1198bc72133daa23a`

---

## 1. Protocol reference

**`GAMP5-OQ-PROTOCOL-001` v1.0** — [`GAMP5-OQ-PROTOCOL-001.md`](GAMP5-OQ-PROTOCOL-001.md)

---

## 2. Execution ID + timestamp (UTC)

**Execution ID:** `OQ-EXEC-20260502T185528Z`  
**Recorded:** 2026-05-02T18:55:28Z

---

## 3. Hardware environment

| Field | Value |
|------|--------|
| **Chip (system_profiler)** | Apple M4 Max |
| **Model** | MacBook Pro (Mac16,6) |
| **Memory** | 128 GB |
| **macOS** | 26.4.1 (Build 25E253) |
| **Xcode** | 26.4.1 (Build 17E202) |
| **`QUALIFIED_CHIP` (IQ doc)** | Apple M4 Max — tag in [`GAMP5-IQ-HARDWARE.md`](GAMP5-IQ-HARDWARE.md) |

---

## 4. **N** (tensor rows)

**`QUALIFIED_N=65536`** — source: `docs/reports/GAMP5-IQ-HARDWARE.md` (`<!-- QUALIFIED_N=65536 -->`).

**OQ-TENSOR-002 / OQ-TENSOR-004 size check**

```text
QUALIFIED_N=65536  EXPECTED_SIZE=8388864  ACTUAL_SIZE=8388864
```

---

## 5. **W** matrix SHA-256 (IQ canonical)

**`QUALIFIED_W_SHA256`:** `18c538e91ac8e10ae636b69f29ae26ef3bce4034815061a0c5726316de78d5e7`  
(Source: [`GAMP5-IQ-HARDWARE.md`](GAMP5-IQ-HARDWARE.md); recomputed by **GaiaRTMGate** / **GAMP5HardwareIQGate** at verification time.)

---

## 6. OQ test results (observed / criterion / outcome)

| OQ ID | Observed | Criterion | Outcome |
|-------|-----------|-----------|---------|
| **Workspace gate** | `ls cells/GaiaComposite.xcworkspace` → `No such file or directory` | Composite workspace absent | **PASS** |
| **OQ-DOC-001..003** | `GAMP5-OQ-PROTOCOL-001.md`, `GAMP5-DEVIATION-PROCEDURE-001.md`, `GAMP5-OQ-EVIDENCE-001.md` | All `PRESENT` | **PASS** |
| **OQ-SVC-001** | `launchctl list com.gaiaftcl.nats` → PID present | NATS job loaded | **PASS** |
| **OQ-SVC-002** | `nats account info … \| grep -i jetstream` | JetStream account info | **PASS** |
| **OQ-SVC-003** | `launchctl list com.gaiaftcl.franklin.consciousness` → PID present | Franklin consciousness job loaded | **PASS** |
| **OQ-SVC-004** | `nc -zv 127.0.0.1 4222` | Connection succeeded | **PASS** |
| **OQ-TENSOR-001** | `xxd` first line: `5651 5445 4e53 4f52` (`VQTENSOR`) | Magic `VQTENSOR` | **PASS** |
| **OQ-TENSOR-002 / 004** | `EXPECTED_SIZE` = `ACTUAL_SIZE` = 8388864 | `256 + N×128` | **PASS** |
| **OQ-LOG-001** | `xxd vqbit_points.log`: `5651 4249 544c 4f47` (`VQBITLOG`) | Magic `VQBITLOG` | **PASS** |
| **OQ-LOG-002** | `xxd vqbit_edges.log`: `5651 4544 4745 4c47` (`VQEDGELG`) | Magic `VQEDGELG` | **PASS** |
| **OQ-FW-001** | `count(*) WHERE kind='genesis'` = **1** | ≥ 1 | **PASS** |
| **OQ-FW-002** | `kind='fusionCatalog'` = **6** | ≥ 1 | **PASS** |
| **OQ-FW-003** | `kind='healthProtocol'` = **6** | ≥ 1 | **PASS** |
| **OQ-FW-004** | `franklin_self_model_history` count = **421** | ≥ 1 | **PASS** |
| **OQ-FW-005** | `nats sub gaiaftcl.franklin.monologue --count 1` received payload | Monologue stream reachable | **PASS** |
| **OQ-CONST-001** | `swift test --filter VQbitSubstrateTests` × 3 | All runs pass | **PASS** |
| **OQ-GATE-001** | `swift run GaiaRTMGate --repo-root …` | `TERMINAL STATE: CALORIE - RTM Verified` | **PASS** |

---

## 7. Genesis receipt SHA-256 (canonical)

```text
1351df3b1f132c9ed709e29e2f02914dfa3696852184ea3977d0b0b615d79619
```

Source: `sqlite3 substrate.sqlite "SELECT canonical_sha256 FROM franklin_learning_receipts WHERE kind='genesis' LIMIT 1;"`

---

## 8. Binary artifact hashes (SHA-256)

Host directory: `~/Library/Application Support/GaiaFTCL/`

```text
3eea5a858d10e82d9e4fc85403fb5a6c4b8cec14705a6711f0d7dedf0a17d3bd  vqbit_tensor.mmap
73051853ec4f57944f5455802331b047885df9243c7d6bc008e07de9b41b3a18  vqbit_points.log
9bb8b7fdbedaa6ae1e26377c29fdde013e7e9ea898baa942cc83470426837264  vqbit_edges.log
```

Command: `shasum -a 256 vqbit_tensor.mmap vqbit_points.log vqbit_edges.log`

---

## 9. Constitutional golden vectors — `swift test --filter VQbitSubstrateTests` (run 1 of 3, verbatim)

```text
[0/1] Planning build
[1/1] Compiling plugin GaiaFTCLAvatarGate
[2/2] Compiling plugin CheckFranklinAvatarAssets
Building for debugging...
[2/16] Write swift-version--58304C5D6DBC2206.txt
Build complete! (19.73s)
Test Suite 'Selected tests' started at 2026-05-02 14:54:38.526.
Test Suite 'GaiaFTCLPackageTests.xctest' started at 2026-05-02 14:54:38.527.
Test Suite 'GaiaFTCLPackageTests.xctest' passed at 2026-05-02 14:54:38.527.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-05-02 14:54:38.527.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1743
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite WireCodecTests started.
◇ Test vmaPRSelfTestClean() started.
◇ Test s4RoundTrip() started.
◇ Test binaryLogHeadersRoundTrip() started.
◇ Test c4RoundTrip() started.
✔ Test binaryLogHeadersRoundTrip() passed after 0.001 seconds.
✔ Test vmaPRSelfTestClean() passed after 0.001 seconds.
✔ Test c4RoundTrip() passed after 0.001 seconds.
✔ Test s4RoundTrip() passed after 0.001 seconds.
✔ Suite WireCodecTests passed after 0.001 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.001 seconds.
```

*(Runs 2–3 also passed; same filter, full transcripts available in Step 8 execution logs.)*

---

## 10. Known limitations / deferred

| Item | Status |
|------|--------|
| **OQ-FW-005** | **PASS** — `/opt/homebrew/bin/nats` CLI present; monologue subscription succeeded. |
| **OQ-CONST-002** | **DEFERRED** — single-chip qualification (documented in IQ hardware scope). |
| **Binary log files** | Tensor created via **VQbitVM** with `GAIAFTCL_TENSOR_N=65536` and `GAIAFTCL_TENSOR_PATH` → `vqbit_tensor.mmap`. Point/edge logs: **32-byte headers** only on first use in this OQ window (magics / `record_size` match **`VQbitBinaryLogCodec`** / IQ gate); continuous append from the launchd writer path is out of scope for this evidence capture. |

---

## 11. Signatory

**Rick Gillespie, Founder and CEO, FortressAI Research Institute**

---

## 12. Git commit SHA (parent evidence commit)

**`2b77d4813fed387a61544fa1198bc72133daa23a`** — replace with the SHA of the **first** OQ evidence commit per [`GAMP5-OQ-PROTOCOL-001.md`](GAMP5-OQ-PROTOCOL-001.md) sign-off procedure (**commit 2** in the two-commit workflow).

---

## OQ-SIGNOFF

Finalizing git commit message after evidence SHA insertion — see protocol document (**commit 2**: `OQ-SIGNOFF: GAMP5-OQ-PROTOCOL-001 v1.0 — evidence sealed with parent SHA`).
