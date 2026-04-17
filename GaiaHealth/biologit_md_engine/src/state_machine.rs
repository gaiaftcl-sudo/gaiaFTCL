//! Biological Cell State Machine
//!
//! Implements the 11-state deterministic transition matrix from the
//! GaiaHealth DQ specification. The layout mode is driven by state —
//! state is NEVER driven by layout mode.
//!
//! State 0:  IDLE
//! State 1:  MOORED
//! State 2:  PREPARED
//! State 3:  RUNNING
//! State 4:  ANALYSIS
//! State 5:  CURE
//! State 6:  REFUSED
//! State 7:  CONSTITUTIONAL_FLAG
//! State 8:  CONSENT_GATE
//! State 9:  TRAINING
//! State 10: AUDIT_HOLD

#[repr(u32)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BiologicalCellState {
    Idle              = 0,
    Moored            = 1,
    Prepared          = 2,
    Running           = 3,
    Analysis          = 4,
    Cure              = 5,
    Refused           = 6,
    ConstitutionalFlag = 7,
    ConsentGate       = 8,
    Training          = 9,
    AuditHold         = 10,
}

impl BiologicalCellState {
    pub fn from_u32(v: u32) -> Self {
        match v {
            0  => Self::Idle,
            1  => Self::Moored,
            2  => Self::Prepared,
            3  => Self::Running,
            4  => Self::Analysis,
            5  => Self::Cure,
            6  => Self::Refused,
            7  => Self::ConstitutionalFlag,
            8  => Self::ConsentGate,
            9  => Self::Training,
            10 => Self::AuditHold,
            _  => Self::Idle,
        }
    }

    /// Forced layout mode for this state (passed to Swift CompositeLayoutManager).
    /// Returns a u32 layout mode constant:
    ///   0 = .researchFocus   (Metal opacity 0.10, WebView opacity 1.00)
    ///   1 = .molecularFocus  (Metal opacity 1.00, WebView opacity 0.00)
    ///   2 = .cellAlarm       (Metal opacity 1.00, WebView opacity 0.85, locked)
    pub fn forced_layout_mode(&self) -> u32 {
        match self {
            Self::Idle | Self::Moored | Self::Prepared
            | Self::Cure | Self::Refused | Self::Training
            | Self::ConsentGate | Self::AuditHold       => 0, // .researchFocus
            Self::Running | Self::Analysis               => 1, // .molecularFocus
            Self::ConstitutionalFlag                     => 2, // .cellAlarm
        }
    }

    /// Metal renderer opacity for this state (0–100, maps to 0.0–1.0).
    pub fn metal_opacity_pct(&self) -> u32 {
        match self.forced_layout_mode() {
            0 => 10,
            1 | 2 => 100,
            _ => 10,
        }
    }

    /// Whether researcher override of layout mode is permitted.
    pub fn researcher_override_permitted(&self) -> bool {
        !matches!(self, Self::ConstitutionalFlag | Self::ConsentGate | Self::AuditHold)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransitionResult {
    Allowed,
    Rejected,
}

/// Validate a state transition against the DQ specification matrix.
///
/// The WASM substrate enforces ANALYSIS→CURE and ANALYSIS→REFUSED.
/// This function enforces the researcher-driven transitions.
///
/// AUDIT_HOLD can be reached from any state (regulatory hold).
pub fn validate_transition(
    from: BiologicalCellState,
    to:   BiologicalCellState,
) -> TransitionResult {
    use BiologicalCellState::*;
    use TransitionResult::*;

    // Any state → AUDIT_HOLD (regulatory hold, always permitted)
    if to == AuditHold { return Allowed; }

    let allowed = match (&from, &to) {
        // Researcher-driven forward path
        (Idle,              Moored)           => true,
        (Idle,              Training)         => true,
        (Moored,            Prepared)         => true,
        (Moored,            ConsentGate)      => true,  // consent expiry
        (Moored,            Idle)             => true,  // session cancel / cleanup
        (Prepared,          Running)          => true,  // WASM force_field_bounds_check must pass
        (Running,           Analysis)         => true,  // automatic on timestep completion
        (Running,           ConstitutionalFlag) => true, // automatic WASM alarm
        (Analysis,          Cure)             => true,  // automatic WASM constitutional pass
        (Analysis,          Refused)          => true,  // automatic WASM ADMET/constitutional fail

        // Recovery paths
        (ConstitutionalFlag, Prepared)        => true,  // R3 PI acknowledgement + root cause
        (ConstitutionalFlag, Idle)            => true,  // R2 emergency exit
        (Cure,              Prepared)         => true,  // next lead optimization iteration
        (Refused,           Prepared)         => true,  // modify molecular approach
        (ConsentGate,       Moored)           => true,  // Owl re-confirms consent
        (ConsentGate,       Idle)             => true,  // Owl withdraws consent

        // Training
        (Training,          Idle)             => true,

        // AuditHold exit (only R3 can clear; modelled as IDLE for now)
        (AuditHold,         Idle)             => true,

        // IDLE → IDLE (no-op, permit for initialization)
        (Idle,              Idle)             => true,

        _ => false,
    };

    if allowed { Allowed } else { Rejected }
}

#[cfg(test)]
mod tests {
    use super::*;
    use BiologicalCellState::*;
    use TransitionResult::*;

    #[test]
    fn tp_001_valid_full_cure_path() {
        // IDLE → MOORED → PREPARED → RUNNING → ANALYSIS → CURE
        let path = [Idle, Moored, Prepared, Running, Analysis, Cure];
        let mut state = path[0].clone();
        for &ref next in &path[1..] {
            let result = validate_transition(state, next.clone());
            assert_eq!(result, Allowed, "transition to {:?} must be allowed", next);
            state = next.clone();
        }
    }

    #[test]
    fn tp_002_valid_refused_path() {
        let result = validate_transition(Analysis, Refused);
        assert_eq!(result, Allowed);
    }

    #[test]
    fn tn_003_idle_to_running_rejected() {
        assert_eq!(validate_transition(Idle, Running), Rejected);
    }

    #[test]
    fn tn_004_idle_to_analysis_rejected() {
        assert_eq!(validate_transition(Idle, Analysis), Rejected);
    }

    #[test]
    fn tc_004_any_state_to_audit_hold_allowed() {
        for state_id in 0u32..=10 {
            let from = BiologicalCellState::from_u32(state_id);
            assert_eq!(
                validate_transition(from, AuditHold),
                Allowed,
                "any state must reach AUDIT_HOLD"
            );
        }
    }

    #[test]
    fn tp_003_layout_mode_idle_is_research_focus() {
        assert_eq!(Idle.forced_layout_mode(), 0);
        assert_eq!(Idle.metal_opacity_pct(), 10);
    }

    #[test]
    fn tp_004_layout_mode_running_is_molecular_focus() {
        assert_eq!(Running.forced_layout_mode(), 1);
        assert_eq!(Running.metal_opacity_pct(), 100);
    }

    #[test]
    fn tp_005_layout_mode_constitutional_flag_is_cell_alarm() {
        assert_eq!(ConstitutionalFlag.forced_layout_mode(), 2);
        assert!(!ConstitutionalFlag.researcher_override_permitted());
    }
}
