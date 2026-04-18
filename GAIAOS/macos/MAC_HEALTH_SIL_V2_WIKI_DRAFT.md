# MacHealth SIL V2 — Test matrix (wiki draft)

Paste into the GitHub Wiki for `gaiaFTCL` as a page such as **MacHealth SIL V2**.

| Item | Detail |
|------|--------|
| Canonical spec | `Scenarios_Physics_Frequencies_Assertions.md` at repository root |
| Swift unit contracts | `GAIAOS/macos/MacHealth/Tests/SILV2/` |
| CI workflow | `.github/workflows/machealth-sil-v2-ci.yml` → `swift test` in `GAIAOS/macos/MacHealth` |
| Cross-cutting §0 | M_SIL provenance; nonce ρ ≥ 0.95 / RMSE ≤ 0.10; filter + TX envelopes; Nyquist; Arrhenius Ω_healthy < 1; RI lock; phase lock; control discrimination; receipt §10 mandatory blocks |
| Receipt ingest gate | Missing any of `ri_lock`, `resonance_detection`, `destructive_interference`, `arrhenius`, `nonce_reconstruction`, `filter_envelope`, `tx_envelope` → REFUSED |

## Seven scenarios (summary)

| # | ID | Notes |
|---|-----|--------|
| 1 | `inv3_aml` | RI leukemic 1.390 vs 1.376; EVI1 cross-probe coherence; 180° ± 5°; Δn boundary correction |
| 2 | `parkinsons_synuclein_thz` | THz 0.42–0.60 THz; F1 ≥ 0.85; ABORT if &lt;10 MHz claims fibril engagement |
| 3 | `msl_tnbc` | Mesenchymal Stem-Like TNBC — motility, geometry, tensor alignment, node hit fraction |
| 4 | `breast_cancer_general_thz` | THz 0.15–3.5 THz; Δn/Δκ contrast; margin IoU; Arrhenius on healthy voxels |
| 5 | `colon_cancer_thz` | THz 0.2–1.4 THz; HT-29/HCT-116 profile; ε tolerances; RI latch ≥ 30 s |
| 6 | `lung_cancer_thz_thermal` | ε ratio; respiratory corr; throttle ≤ 10 ms; Arrhenius on vascularized lung |
| 7 | `skin_cancer_bcc_melanoma` | 0.25–0.90 THz; f₀ 1.651 vs 1.659 THz; tryptophan 1.42/1.84 THz; anti-lock margin |

**Not a clinical trial or therapy claim** — substrate-correctness bars only (see spec §11).
