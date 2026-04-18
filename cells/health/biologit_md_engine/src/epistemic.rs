//! M/I/A Epistemic Classification Spine
//!
//! Every numerical output produced by the biological cell carries a mandatory
//! epistemic tag. No value is presented without its classification.
//!
//! M — Measured:  ITC assays, SPR kinetics, NMR, X-ray crystallography. Highest trust.
//! I — Inferred:  MD simulation ΔG, AutoDock scores, AlphaFold predictions. Medium trust.
//! A — Assumed:   Literature values, population statistics, reference constants. Lowest trust.
//!
//! CURE terminal state requires M or I. A CURE relying solely on Assumed data
//! is automatically shunted to REFUSED with fault ASSUMED_BINDING_NOT_VALIDATED.

#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpistemicTag {
    Measured = 0,
    Inferred = 1,
    Assumed  = 2,
}

impl EpistemicTag {
    pub fn from_u32(v: u32) -> Self {
        match v {
            0 => Self::Measured,
            1 => Self::Inferred,
            _ => Self::Assumed,
        }
    }

    /// Metal renderer alpha for this epistemic level (0–100).
    /// M = 100% opaque (solid), I = 60% (translucent), A = 30% (stippled/faded)
    pub fn metal_alpha_pct(&self) -> u32 {
        match self {
            Self::Measured => 100,
            Self::Inferred =>  60,
            Self::Assumed  =>  30,
        }
    }

    /// Whether this tag permits a CURE terminal state.
    /// Only M and I may produce CURE; A alone yields REFUSED.
    pub fn permits_cure(&self) -> bool {
        matches!(self, Self::Measured | Self::Inferred)
    }

    /// Label for audit log (no PHI — purely computational provenance).
    pub fn audit_label(&self) -> &'static str {
        match self {
            Self::Measured => "M",
            Self::Inferred => "I",
            Self::Assumed  => "A",
        }
    }
}

/// Validate that an epistemic chain is complete and consistent from
/// input dataset to final output. Returns Ok(tag) or Err(fault_code).
///
/// fault_code "ASSUMED_BINDING_NOT_VALIDATED" triggers REFUSED.
pub fn validate_epistemic_chain(
    input_tag:     EpistemicTag,
    computation_tag: EpistemicTag,
    output_tag:    EpistemicTag,
) -> Result<EpistemicTag, &'static str> {
    // The chain cannot upgrade — output cannot be more trusted than input
    let input_rank = input_tag as u32;
    let output_rank = output_tag as u32;
    if output_rank < input_rank {
        return Err("EPISTEMIC_UPGRADE_VIOLATION");
    }

    // A-only output cannot produce CURE
    if output_tag == EpistemicTag::Assumed && computation_tag == EpistemicTag::Assumed {
        return Err("ASSUMED_BINDING_NOT_VALIDATED");
    }

    // Return the least-trusted tag in the chain (conservative)
    let min_rank = input_rank.max(computation_tag as u32).max(output_rank);
    Ok(EpistemicTag::from_u32(min_rank))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tp_006_measured_permits_cure() {
        assert!(EpistemicTag::Measured.permits_cure());
    }

    #[test]
    fn tp_007_inferred_permits_cure() {
        assert!(EpistemicTag::Inferred.permits_cure());
    }

    #[test]
    fn tc_005_assumed_alone_refused() {
        assert!(!EpistemicTag::Assumed.permits_cure());
        let result = validate_epistemic_chain(
            EpistemicTag::Assumed,
            EpistemicTag::Assumed,
            EpistemicTag::Assumed,
        );
        assert_eq!(result, Err("ASSUMED_BINDING_NOT_VALIDATED"));
    }

    #[test]
    fn tp_008_metal_alpha_ordering() {
        assert!(EpistemicTag::Measured.metal_alpha_pct() > EpistemicTag::Inferred.metal_alpha_pct());
        assert!(EpistemicTag::Inferred.metal_alpha_pct() > EpistemicTag::Assumed.metal_alpha_pct());
    }

    #[test]
    fn tc_006_epistemic_upgrade_violation() {
        // Cannot claim output is Measured if input was Inferred
        let result = validate_epistemic_chain(
            EpistemicTag::Inferred,
            EpistemicTag::Inferred,
            EpistemicTag::Measured, // illegal upgrade
        );
        assert_eq!(result, Err("EPISTEMIC_UPGRADE_VIOLATION"));
    }
}
