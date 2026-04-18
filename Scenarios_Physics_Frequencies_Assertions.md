# Seven Clinical Scenarios — Frequencies, Refractive Indices, Arrhenius Thresholds, and What Automated Tests Must Assert

**Automated unit contract (Swift):** `cells/fusion/macos/MacHealth/Tests/SILV2/` — XCTest validates §0 cross-rails, §10 receipt schema completeness, and per-scenario thresholds from §1–§7 (`validation_tier: SIL_protocol_contract`).

**Date:** 2026-04-18
**Scope:** inv(3) AML, Parkinson's, MSL (Mesenchymal Stem-Like) TNBC, breast cancer (general), colon cancer, lung cancer, **and** skin cancer (BCC + melanoma).
**Framework:** GaiaHealth SIL V2 substrate. Every assertion here is expressed as a receipt-schema-enforced contract and inherits the SIL V2 envelope (nonce reconstruction ρ ≥ 0.95 / RMSE ≤ 0.10; filter tolerances ≤ 5 % / ≤ 10 ° / > 40 dB at 60 Hz; TX envelope; M_SIL provenance; refusal over guess).
**Physical primitives introduced:** native resonant frequency (f₀), localized complex refractive index ñ = n + iκ, Arrhenius thermodynamic damage integral Ω = ∫ A · exp(−Eₐ / RT(t)) dt, tensor wavefront correction, destructive-interference phase lock.

> **Correction vs an earlier draft:** "MSL" here means **Mesenchymal Stem-Like TNBC** (motile, EMT-enriched breast-cancer subtype), not Madelung's disease.

---

## 0. Cross-cutting contract (applies to every scenario)

Every scenario test SHALL, in addition to its scenario-specific asserts:

1. **Provenance.** `provenance_tag == "M_SIL"` during SIL runs; any `"M"` leak is `REFUSED` with reason `"provenance_tag_leak"`.
2. **Nonce reconstruction** (§3.2 SIL V2): ρ ≥ 0.95 and RMSE/peak ≤ 0.10 over t ∈ [60 s, 300 s]. Failure → `REFUSED: nonce_reconstruction_failed`.
3. **Filter envelope** (§3.2): amplitude error ≤ 5 %, phase error ≤ 10 °, 60 Hz rejection > 40 dB at t ≥ 60 s.
4. **TX envelope** (§3.3): Freq ± 0.1 Hz, Phase ± 5 °, Duty ± 1 %, Amplitude ± 2 %, Latency ≤ 500 ms p99.
5. **Nyquist / band-gate.** `plant_config.sampling_rate_hz > 2 × f_max_asserted`. For THz channels, the plant MUST declare a THz sampler or a heterodyne-down optical/electronic mixer; IQ fails otherwise. Violations are a plant-config error, not an OQ miss.
6. **Arrhenius thermal guard.** Wherever a THz projection is emitted, the substrate MUST continuously evaluate
   `Ω_local(t) = ∫₀ᵗ A · exp(−Eₐ / R · T(τ)) dτ`
   against the **healthy-tissue** Eₐ threshold for that compartment and **throttle dose rate** before Ω_local exceeds 1. Failure to throttle is `REFUSED: arrhenius_saturation_breached`.
7. **Refractive-index lock.** Every scenario that names an RI MUST assert the measured complex RI `ñ` matches the scenario's declared `ñ_target` within the declared tolerance **before** any destructive-interference payload is emitted. Missing RI lock → `REFUSED: ri_lock_not_acquired`.
8. **Destructive-interference phase lock.** Where the scenario calls for a destructive-interference wave, the emitted payload MUST be 180 ° ± 5 ° out-of-phase with the measured native resonance over a latched ≥ 60 s window. Phase out-of-spec → `REFUSED: phase_lock_out_of_spec`.
9. **Control discrimination.** Every scenario ships a list of look-alikes the substrate MUST `REFUSE` on. A clean run with no look-alike refusals is suspect and is flagged `suspicious_clean`.
10. **Receipt.** Every OQ run emits the receipt schema in §10.

---

## 1. inv(3) Acute Myeloid Leukemia — `inv(3)(q21q26.2)` / `t(3;3)`

### 1a. Physics & frequencies

- **Pathogenesis:** topological routing error — the **G2DHE enhancer** (distal *GATA2* 3q21 enhancer) is hijacked onto the **EVI1/MECOM** locus at 3q26, producing a specific aberrant chromatin loop and MECOM over-expression with GATA2 haploinsufficiency.
- **Cellular optics:** leukemic blasts carry an **elevated refractive index n = 1.390** vs normal blood cells at **n = 1.376** (Δn ≈ 0.014). This boundary causes wavefront distortion and premature phase-shift if not corrected.
- **Target resonance:** the aberrant EVI1 transcription loop has native acoustic + electromagnetic resonance characteristic of the hijacked 3D chromatin architecture.

### 1b. Required automated assertions

```yaml
scenario: inv3_aml
plant_config:
  sampling_rate_hz: 5.0e10          # heterodyne-down channel; f_max ≈ 25 GHz
  max_state_transition_hz: 1.0e10
required_channels: [ri_sensor, acoustic_probe, em_probe, thermal_probe]
asserts:
  - name: ri_lock_leukemic
    n_real_target: 1.390
    n_real_tolerance: 0.003
    k_imag_tolerance: 0.002
    hold_duration_s_min: 60
  - name: ri_discrimination_vs_normal
    # Substrate must NOT flag RI=1.376 as leukemic.
    control_ri: 1.376
    expected_outcome: REFUSED
    expected_reason: "ri_normal_blood"
  - name: evi1_loop_resonance_detection
    # Substrate measures native resonance of the aberrant chromatin loop on
    # both acoustic and EM probes, cross-validates the two.
    detect_on: [acoustic_probe, em_probe]
    cross_probe_coherence_min: 0.85
  - name: destructive_interference_phase_lock
    payload_phase_rel_to_resonance_deg: { target: 180.0, tolerance: 5.0 }
    latched_duration_s_min: 60
  - name: wavefront_ri_correction
    # Active correction must compensate for the Δn = 0.014 boundary.
    compensation_enabled: true
    residual_phase_error_deg_max: 3.0
  - name: arrhenius_guard
    tissue: healthy_marrow_stroma
    Ea_kJ_per_mol: 340            # canonical denatur. window for healthy stroma (plant-config overridable)
    omega_max: 1.0
    throttle_on_exceed: true
refusal_conditions:
  - reason: "ri_lock_not_acquired"
    when: "abs(n_real - 1.390) > 0.003 for >10s"
  - reason: "phase_lock_out_of_spec"
    when: "abs(phase_deg - 180) > 5"
  - reason: "arrhenius_saturation_breached"
    when: "omega_local >= 1.0"
  - reason: "mecom_gata2_contradiction"
    when: "mecom_foldchange < 1.2 AND gata2_foldchange > 0.8"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - normal_cd34_progenitor_ri_1376
    - mll_rearranged_aml_non_inv3       # different loop architecture
    - cml_bcr_abl                        # must REFUSE
```

---

## 2. Parkinson's Disease

### 2a. Physics & frequencies

- **Pathology target:** aggregated **α-synuclein fibrils** (Lewy pathology). The fibrils themselves are **acoustically silent in 10 kHz – 10 MHz** — any protocol using that band cannot interact with or detect them.
- **THz signature:** α-synuclein fibrils carry measurable transmission and amplitude **resonance peaks in 0.42 – 0.60 THz**. Mutant variants (A53T, A30P) show distinct peaks within this window vs wild type.
- **Consequence for protocols:** a targeting protocol MUST sweep within 0.42 – 0.60 THz; MUST abort if it finds itself emitting anywhere < 10 MHz and claiming fibril interaction.

### 2b. Required automated assertions

```yaml
scenario: parkinsons_synuclein_thz
plant_config:
  sampling_rate_hz: 2.0e12           # ≥ 2 × 1 THz (Nyquist) on THz channel
  max_state_transition_hz: 1.0e12
required_channels: [thz_sweeper, ri_sensor, thermal_probe]
asserts:
  - name: thz_sweep_window
    sweep_start_hz: 4.2e11
    sweep_stop_hz:  6.0e11
    sweep_duration_s_min: 1.0
    dwell_hz_resolution_max: 5.0e8     # ≤ 0.5 GHz step inside the 0.42–0.60 THz window
  - name: mutant_peak_discrimination
    # Substrate must classify WT vs A53T vs A30P from transmission/amplitude
    # resonance fingerprints inside the sweep window.
    classes: [WT, A53T, A30P]
    class_f1_min: 0.85
  - name: acoustic_band_abort
    # If any emitter active < 10 MHz is labeled as fibril-targeting, abort.
    forbidden_band_hz: [0, 1.0e7]
    on_violation: ABORT
    expected_reason: "acoustic_band_cannot_interact_with_fibrils"
  - name: fibril_only_engagement
    # No engagement claim permitted without a THz peak lock in 0.42–0.60 THz.
    engagement_requires_peak_in_hz: [4.2e11, 6.0e11]
  - name: arrhenius_guard
    tissue: healthy_nigral_parenchyma
    Ea_kJ_per_mol: 320
    omega_max: 1.0
    throttle_on_exceed: true
refusal_conditions:
  - reason: "out_of_band_emission"
    when: "peak_emission_hz NOT IN [4.2e11, 6.0e11]"
  - reason: "acoustic_band_violation"
    when: "any_emitter_hz < 1.0e7 AND claim == 'fibril_engagement'"
  - reason: "no_mutant_peak_match"
    when: "peak_count_in_window < 1"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - wildtype_synuclein_no_mutation
    - beta_amyloid_alzheimer            # different THz fingerprint
    - tau_tangles                       # different THz fingerprint
    - essential_tremor_no_synuclein
```

**Why strict:** PD in a THz-protocol context has a *hard* forbidden band (acoustic) and a *hard* required band (0.42–0.60 THz). A substrate that engages anywhere else and claims fibril interaction is unsafe, not just wrong.

---

## 3. Mesenchymal Stem-Like (MSL) TNBC

### 3a. Physics & frequencies

- **Subtype:** MSL is a **motile, EMT-enriched TNBC** subtype (Lehmann classification) — gene expression weighted toward epithelial-mesenchymal-transition and cell-motility pathways.
- **Mechanical / geometric signature:** distinct **structural density** and **surface geometry** vs other TNBC subtypes; higher motility + altered cytoskeletal tensor.
- **Targeting consequence:** a tensor-wave protocol must map the **motility pathway geometry** and apply **tensor-corrected** projections so resonance nodes shatter in the correct cytoskeletal locations, not in stromal bystanders.

### 3b. Required automated assertions

```yaml
scenario: msl_tnbc
plant_config:
  sampling_rate_hz: 2.5e10
  max_state_transition_hz: 1.0e10
required_channels: [thz_imager, ri_sensor, tensor_probe, motility_tracker]
asserts:
  - name: emt_gene_signature_surrogate
    # PyGen emits a scalar channel encoding EMT/motility score.
    score_min: 0.6
  - name: surface_geometry_map_completeness
    # Fraction of tumor perimeter with valid geometry estimate.
    coverage_fraction_min: 0.90
    voxel_edge_m_max: 5.0e-6            # ≤ 5 µm per voxel
  - name: motility_vector_field_coherence
    # Time-lapsed cell motility vectors must have non-zero coherence,
    # distinguishing MSL from static (non-motile) TNBC subtypes.
    coherence_min: 0.5
    frames_per_second_min: 2.0
  - name: tensor_wave_alignment
    # Applied tensor wave must align to cytoskeletal tensor within tolerance.
    tensor_alignment_cosine_min: 0.85
  - name: ri_map_spatial_variance
    # MSL heterogeneity → elevated spatial RI variance vs homogeneous subtypes.
    ri_variance_min: 1.0e-4
  - name: resonance_node_targeting_accuracy
    # Fraction of intended cytoskeletal nodes that the shatter pattern hit.
    target_hit_fraction_min: 0.80
    off_target_fraction_max: 0.05
  - name: arrhenius_guard
    tissue: healthy_breast_stroma
    Ea_kJ_per_mol: 300
    omega_max: 1.0
    throttle_on_exceed: true
refusal_conditions:
  - reason: "non_motile_profile"
    when: "motility_coherence < 0.2"
  - reason: "wrong_tnbc_subtype"
    when: "emt_score < 0.4 AND luminal_androgen_receptor_score > 0.5"
  - reason: "tensor_misalignment"
    when: "tensor_alignment_cosine < 0.7"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - basal_like_1_tnbc                 # BL1 — not motility-enriched
    - basal_like_2_tnbc                 # BL2 — different signature
    - luminal_androgen_receptor_tnbc    # LAR — must REFUSE
    - immunomodulatory_tnbc_IM          # IM — must REFUSE
```

---

## 4. Breast Cancer (general)

### 4a. Physics & frequencies

- **Optical/THz contrast:** malignant breast tumor has **significantly higher complex refractive index** (both n and κ) and **higher absorption coefficient α(f)** than healthy fibrous or adipose breast tissue.
- **Operational THz window:** **0.15 – 3.5 THz** — optimal for mapping malignant margins and maintaining penetration-vs-resolution balance.
- **Thermal constraint:** localized Δ E_metab (metabolic / absorbed-energy accumulation) must remain **below the Arrhenius activation-energy threshold for healthy tissue** at every voxel, else unintended thermal necrosis.

### 4b. Required automated assertions

```yaml
scenario: breast_cancer_general_thz
plant_config:
  sampling_rate_hz: 7.0e12           # ≥ 2 × 3.5 THz
  max_state_transition_hz: 3.5e12
required_channels: [thz_sweeper, ri_sensor_complex, absorption_spectrometer, thermal_probe]
asserts:
  - name: thz_window_lock
    sweep_start_hz: 1.5e11
    sweep_stop_hz:  3.5e12
    off_window_rejection_db_min: 40
  - name: complex_refractive_index_contrast
    # Tumor vs healthy fibro/adipose must exceed tolerance in both n and κ.
    tumor_n_real_min_minus_healthy: 0.08
    tumor_k_imag_min_minus_healthy: 0.03
    healthy_ranges:
      fibroglandular_n_real: [1.40, 1.48]
      adipose_n_real:        [1.42, 1.46]
  - name: absorption_coefficient_contrast
    # α(f) in 1/cm averaged over window.
    alpha_tumor_over_healthy_min: 1.8
  - name: margin_localization_accuracy
    # Against a PyGen-declared ground-truth margin in the plant, IoU must
    # exceed threshold before any destructive payload is emitted.
    margin_iou_min: 0.85
  - name: arrhenius_thermal_guard_healthy
    tissue: healthy_fibroglandular_and_adipose
    Ea_kJ_per_mol: 310
    omega_max_healthy: 1.0
    dose_rate_throttle_enabled: true
    healthy_voxel_protection_fraction_min: 0.99
  - name: delta_E_metab_ceiling
    # Accumulated metabolic/absorbed energy per healthy voxel must stay
    # below E_a threshold at all t.
    per_voxel_ceiling_joules: plant_defined
    guarantee: continuous_assertion
refusal_conditions:
  - reason: "out_of_thz_window"
    when: "peak_emission_hz < 1.5e11 OR peak_emission_hz > 3.5e12"
  - reason: "insufficient_complex_ri_contrast"
    when: "tumor_n_real - healthy_n_real_mean < 0.08"
  - reason: "arrhenius_healthy_breach_projected"
    when: "omega_healthy_voxels_predicted >= 1.0 before next_emission"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - fibroadenoma_benign
    - dense_glandular_tissue
    - fat_necrosis
    - silicone_implant_artifact
```

---

## 5. Colon Cancer

### 5a. Physics & frequencies

- **Dielectric / RI signatures:** malignant colon tissues and reference cancer cell lines (**HT-29**, **HCT-116**) show dielectric constants, extinction coefficients κ, and resonant absorption peaks distinct from healthy colonic mucosa.
- **Operational THz band:** **0.2 – 1.4 THz** — the window where the pathological vs healthy contrast is sharpest.
- **Pre-projection check:** the **dynamically measured complex RI** must match the scenario's known pathological RI **before** wave projection begins.

### 5b. Required automated assertions

```yaml
scenario: colon_cancer_thz
plant_config:
  sampling_rate_hz: 3.0e12          # ≥ 2 × 1.4 THz
  max_state_transition_hz: 1.4e12
required_channels: [thz_sweeper, complex_ri_sensor, absorption_spectrometer, thermal_probe]
asserts:
  - name: thz_band_lock
    sweep_start_hz: 2.0e11
    sweep_stop_hz:  1.4e12
    off_window_rejection_db_min: 40
  - name: cell_line_signature_match
    # At IQ the plant declares which cell-line reference profile is loaded.
    allowed_references: [HT-29, HCT-116, patient_derived]
    reference_match_cosine_min: 0.90
  - name: dielectric_constant_match
    # Real and imaginary parts of epsilon(f) must match within tolerance.
    epsilon_real_tolerance_pct: 5
    epsilon_imag_tolerance_pct: 7
  - name: resonant_absorption_peak_count
    # At least two distinct absorption peaks in the 0.2–1.4 THz band
    # that co-localize with the declared reference.
    peaks_in_band_min: 2
    peak_match_cosine_min: 0.85
  - name: pre_projection_ri_lock
    # No wave projection without RI match satisfied for ≥ 30 s.
    locked_duration_s_min: 30
    n_real_tolerance: 0.01
    k_imag_tolerance: 0.01
  - name: arrhenius_guard
    tissue: healthy_colonic_mucosa
    Ea_kJ_per_mol: 290
    omega_max: 1.0
refusal_conditions:
  - reason: "reference_profile_absent"
    when: "declared_reference NOT IN allowed_references"
  - reason: "ri_mismatch"
    when: "cosine_match < 0.85 for 30s"
  - reason: "out_of_thz_band"
    when: "peak_hz < 2.0e11 OR peak_hz > 1.4e12"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - normal_colonic_mucosa
    - ibd_active_inflammation
    - diverticulitis_wall_thickening
    - adenomatous_polyp_benign            # must REFUSE
```

---

## 6. Lung Cancer

### 6a. Physics & frequencies

- **THz absorption contrast:** lung tumor tissue absorbs THz energy faster and more intensely than healthy lung, due to distinct permittivity and **water-to-protein ratio**. Result: rapid localized ΔT spikes possible.
- **Consequence:** heat absorption is the hazard. Dose rate must be **throttled dynamically** against the **Arrhenius kinetic breakpoint of healthy, highly-vascularized lung parenchyma** at every voxel.

### 6b. Required automated assertions

```yaml
scenario: lung_cancer_thz_thermal
plant_config:
  sampling_rate_hz: 7.0e12          # THz window; operator-selected sub-band
  max_state_transition_hz: 3.5e12
required_channels: [thz_sweeper, complex_ri_sensor, thermal_probe_array, perfusion_probe]
asserts:
  - name: permittivity_contrast_tumor_vs_parenchyma
    epsilon_real_ratio_min: 3.0
    epsilon_imag_ratio_min: 2.5
  - name: water_protein_ratio_signature
    # Plant surrogate encodes w/p ratio on a scalar channel.
    tumor_wp_ratio_range: [2.5, 5.0]
    healthy_lung_wp_ratio_range: [0.2, 1.2]
  - name: local_delta_T_rate_cap
    # dT/dt per voxel, healthy parenchyma.
    max_healthy_dT_per_s_celsius: 0.5
  - name: arrhenius_healthy_lung_guard
    tissue: healthy_vascularized_lung
    Ea_kJ_per_mol: 270
    omega_max: 1.0
    vascular_perfusion_weighting: enabled
    throttle_on_exceed: true
    throttle_response_ms_max: 10
  - name: respiratory_gating_correlation
    # Tumor position updates synchronized with respiration; loss of sync
    # aborts the emission.
    respiratory_correlation_min: 0.7
  - name: dose_rate_dynamic_throttle
    # Controller must demonstrate throttle response on synthetic spike.
    injection_spike_watts: plant_defined
    recovery_time_ms_max: 20
refusal_conditions:
  - reason: "arrhenius_healthy_breach_projected"
    when: "omega_healthy_voxels_predicted >= 1.0"
  - reason: "throttle_response_too_slow"
    when: "controller_response_ms > 10"
  - reason: "respiratory_sync_lost"
    when: "correlation < 0.5 for >1s"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - granuloma_calcified
    - hamartoma
    - post_radiation_fibrosis
    - pulmonary_infarct
```

---

## 7. Skin Cancer — Basal Cell Carcinoma (BCC) and Melanoma

### 7a. Physics & frequencies

- **Biophysical contrast window:** BCC differs from healthy skin in **0.25 – 0.90 THz**, with peak absorption deviation ≈ **0.5 THz**.
- **Native cellular resonance shift:** cancerous basal cells resonate at **f₀ = 1.651 THz**, a **7.63 GHz downward shift** from normal basal cells at **1.659 THz**. (1.659 − 1.651 = 0.008 THz = 8 GHz ≈ stated 7.63 GHz within reporting tolerance; assertion uses the exact numbers below.)
- **Intrinsic biomarker resonances:** tryptophan absorbs at **1.42 THz** and **1.84 THz** — required co-signature for non-melanoma skin cancers.
- **Complex-wave features to analyze:** resonance frequency f₀, transmission magnitude |T(f)|, **Full Width at Half Maximum (FWHM)** of the resonance peak.

### 7b. Required automated assertions

```yaml
scenario: skin_cancer_bcc_melanoma
plant_config:
  sampling_rate_hz: 5.0e12          # ≥ 2 × 2 THz for tryptophan peaks
  max_state_transition_hz: 2.0e12
required_channels: [thz_sweeper, ri_sensor_complex, fwhm_analyzer, thermal_probe, epidermal_segmenter]
asserts:
  - name: contrast_window_lock
    sweep_start_hz: 2.5e11
    sweep_stop_hz:  9.0e11
    peak_deviation_hz: { target: 5.0e11, tolerance: 5.0e10 }  # ≈ 0.5 THz ± 50 GHz
  - name: bcc_resonance_downshift_detection
    # Cancerous basal cells resonate at 1.651 THz vs healthy 1.659 THz.
    cancer_f0_hz: { target: 1.651e12, tolerance: 1.0e9 }     # ± 1 GHz
    healthy_f0_hz: { target: 1.659e12, tolerance: 1.0e9 }
    required_downshift_hz: { target: 7.63e9, tolerance: 1.0e9 }
    detection_signal_to_noise_db_min: 12
  - name: tryptophan_biomarker_peaks
    required_peaks_hz:
      - { target: 1.42e12, tolerance: 2.0e9 }
      - { target: 1.84e12, tolerance: 2.0e9 }
    both_required_for_nonmelanoma: true
    peak_amplitude_snr_db_min: 10
  - name: fwhm_analysis
    # FWHM of the 1.651 THz cancer resonance must fall within expected
    # range; broadened FWHM indicates heterogeneity or misidentification.
    fwhm_hz_range: [5.0e9, 3.0e10]
  - name: destructive_interference_phase_lock
    # Payload must be 180° ± 5° out of phase with 1.651 THz cancer
    # resonance, and MUST NOT lock onto 1.659 THz healthy resonance.
    payload_phase_rel_to_cancer_f0_deg: { target: 180.0, tolerance: 5.0 }
    anti_lock_healthy_f0_margin_deg_min: 20
  - name: biomarker_gate_before_emission
    # No destructive emission unless both tryptophan peaks detected AND
    # the 7.63 GHz downshift is latched for ≥ 15 s.
    gate_conditions: [tryptophan_peaks_detected, downshift_latched_15s]
  - name: arrhenius_epidermal_guard
    tissue: healthy_epidermis_and_upper_dermis
    Ea_kJ_per_mol: 280
    omega_max: 1.0
    per_layer_protection:
      stratum_corneum: strict
      basal_layer_healthy: strict
      papillary_dermis: strict
    throttle_on_exceed: true
  - name: melanin_absorption_compensation
    # Melanoma / pigmented lesions: active compensation for melanin
    # absorption to avoid false thermal readings.
    compensation_enabled: true
refusal_conditions:
  - reason: "downshift_not_resolved"
    when: "abs(measured_shift_hz - 7.63e9) > 1.0e9"
  - reason: "tryptophan_peaks_incomplete"
    when: "peaks_detected < 2"
  - reason: "fwhm_out_of_range"
    when: "fwhm_hz < 5.0e9 OR fwhm_hz > 3.0e10"
  - reason: "arrhenius_epidermal_breach_projected"
    when: "omega_epidermis_predicted >= 1.0"
  - reason: "healthy_f0_lock_risk"
    when: "phase_margin_vs_healthy_f0 < 20 deg"
anti_spoofing:
  nonce_reconstruction: required
  control_discrimination_tests:
    - seborrheic_keratosis_benign
    - actinic_keratosis_pre_malignant     # MUST REFUSE destructive payload
    - nevus_benign_mole
    - healthy_basal_layer_1659_thz        # MUST REFUSE — same band, wrong f0
```

**Why strict:** the BCC signature and the healthy signature sit 7.63 GHz apart on adjacent ~1.65 THz resonances. A substrate that locks phase to 1.659 THz by accident would preferentially damage **healthy** basal cells. The `anti_lock_healthy_f0_margin_deg_min` plus `healthy_f0_lock_risk` refusal are the twin safety rails.

---

## 8. Cross-scenario quick reference

| Scenario | Required THz window | Key RI / f₀ | Arrhenius-guarded healthy tissue | Non-negotiable abort rail |
|---|---|---|---|---|
| inv(3) AML | — (RI-mediated EM/acoustic) | n_leukemic = 1.390 vs n_normal = 1.376 | Marrow stroma | 180° phase lock ± 5° |
| Parkinson's | **0.42 – 0.60 THz** | — | Nigral parenchyma | `ABORT` if any emitter < 10 MHz claims fibril engagement |
| MSL TNBC | THz imaging window (plant-declared) | Spatial RI variance ≥ 1e-4 | Breast stroma | Tensor alignment cosine ≥ 0.85 |
| Breast (general) | **0.15 – 3.5 THz** | Δn ≥ 0.08, Δκ ≥ 0.03 vs healthy | Fibroglandular + adipose | Pre-shot Arrhenius projection on healthy voxels |
| Colon | **0.2 – 1.4 THz** | HT-29 / HCT-116 ε(f) match | Colonic mucosa | RI match latched ≥ 30 s before projection |
| Lung | THz (plant sub-band) | ε_tumor/ε_lung ≥ 3×; w/p ≫ 1 | Vascularized lung | Throttle response ≤ 10 ms |
| Skin (BCC/melanoma) | **0.25 – 0.90 THz** + biomarker peaks at **1.42 / 1.84 THz** | f₀_cancer = 1.651 THz vs f₀_healthy = 1.659 THz (Δ ≈ 7.63 GHz) | Epidermis + upper dermis | Anti-lock margin to healthy f₀ ≥ 20° |

---

## 9. Arrhenius thermodynamic-saturation model (shared)

All seven scenarios use the same cumulative-damage integral:

> Ω_healthy(**x**, t) = ∫₀ᵗ A · exp( −Eₐ / [R · T(**x**, τ)] ) dτ

with per-tissue defaults:

| Healthy tissue | Eₐ (kJ/mol) default | A (s⁻¹) default | Source of override |
|---|---|---|---|
| Marrow stroma | 340 | 1 × 10⁴⁰ | plant_config |
| Nigral parenchyma | 320 | 1 × 10⁴⁰ | plant_config |
| Breast stroma (MSL context) | 300 | 3 × 10³⁹ | plant_config |
| Fibroglandular + adipose | 310 | 5 × 10³⁹ | plant_config |
| Colonic mucosa | 290 | 1 × 10³⁹ | plant_config |
| Vascularized lung | 270 | 3 × 10³⁹ + perfusion factor | plant_config |
| Epidermis + upper dermis | 280 | 7 × 10³⁹ | plant_config |

The **substrate controller** MUST reduce dose rate so that the predicted Ω_healthy per voxel stays strictly < 1 for the projected emission horizon. "Predicted and observed" both must be logged; divergence > 0.2 between predicted and observed Ω emits `arrhenius_model_drift`.

---

## 10. Receipt schema contract (binds every scenario)

```json
{
  "scenario": "<name>",
  "run_id": "<uuid>",
  "nonce_128bit_hex": "<hex>",
  "provenance_tag": "M_SIL",
  "plant_config_sha256": "<hex>",
  "substrate_sha256": "<hex>",
  "engine_sha256": "<hex>",
  "wasm_sha256": "<hex>",
  "sweep_window_hz": [f_low, f_high],
  "ri_lock": { "n_real": 0.0, "k_imag": 0.0, "target_n": 0.0, "target_k": 0.0, "locked_duration_s": 0.0, "passed": true },
  "resonance_detection": { "f0_hz": 0.0, "fwhm_hz": 0.0, "snr_db": 0.0, "passed": true },
  "destructive_interference": { "phase_deg_vs_f0": 180.0, "anti_lock_margin_deg": 22.0, "latched_duration_s": 0.0, "passed": true },
  "arrhenius": { "tissue": "...", "Ea_kJ_mol": 310, "omega_max_observed": 0.4, "predicted_vs_observed_delta": 0.05, "throttle_events": 0, "passed": true },
  "nonce_reconstruction": { "pearson_rho": 0.97, "rmse_over_peak": 0.06, "window_s": [60, 300], "passed": true },
  "filter_envelope": { "amplitude_error_pct": 2.1, "phase_error_deg": 3.8, "rejection_60hz_db": 47.2, "passed": true },
  "tx_envelope": { "freq_err_hz": 0.03, "phase_err_deg": 1.9, "duty_err_pct": 0.4, "amp_err_pct": 0.9, "latency_p99_ms": 212, "passed": true },
  "asserts": [ { "name": "...", "passed": true, "observed": { }, "tolerance": { } } ],
  "refusals": [ { "reason": "...", "evidence": { } } ],
  "control_discrimination": [ { "control": "...", "refused": true, "reason": "..." } ],
  "parent_hash": "<hex>",
  "receipt_sig": "<ed25519>"
}
```

Any receipt missing `ri_lock`, `resonance_detection`, `destructive_interference`, `arrhenius`, `nonce_reconstruction`, `filter_envelope`, or `tx_envelope` is REFUSED at ingest regardless of per-assertion results.

---

## 11. What this report is not

- Not a clinical protocol or therapy specification. Every number here is a substrate-correctness bar, not a patient-treatment parameter.
- Not a claim that GaiaHealth / GaiaFTCL treats or diagnoses any condition. The assertions exist so that a correct substrate passes and an incorrect / spoofed substrate fails detectably.
- THz band numbers, RI values, resonance-shift values, and cell-line references are taken from the user's operational-protocol brief (2026-04-18). Arrhenius defaults are order-of-magnitude placeholders; the IQ phase MUST calibrate and pin them against the plant-config checked into the repo before any OQ run emits `passed: true`.
