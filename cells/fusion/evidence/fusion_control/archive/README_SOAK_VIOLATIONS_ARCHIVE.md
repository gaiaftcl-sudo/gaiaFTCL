# Soak violations archive (labeled change)

## What was wrong

Earlier `soak_violations.jsonl` lines were produced when the soak script evaluated **τ against `wall_time_ms`** (full batch path, Mac contention–sensitive). That produced **false positives** relative to the **default Metal gate**, which uses **`gpu_wall_us`** (GPU work) for the hot τ budget.

Receipts in `long_run_signals.jsonl` could show excellent ε and low wall time while the violation file still accumulated lines — **not** because the matrix failed, but because **two different τ metrics** were mixed.

## What changed

- Default soak metric: **`gpu_ms` / `gpu_wall_us`** (aligned with control matrix receipts).
- Optional stress mode: `FUSION_SOAK_TAU_METRIC=wall_ms` for deliberate full-path contention testing.
- **Historical violations** were moved out of the active file into `soak_violations.jsonl.archived.20260404T200548Z` so the **active** `soak_violations.jsonl` tail is **C4 for current policy** only.

## UI / API

The Fusion S4 soak table treats **`long_run_signals.jsonl`** (Metal batches) and **`soak_violations.jsonl`** as **separate rows**. Header **“last matrix receipt”** is **not** the same as the NSTX-U row (which uses the **signals JSONL tail** only).
