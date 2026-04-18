use anyhow::{anyhow, Result};

/// Franklin oversight for `uum8d::QState8` trajectories.
///
/// Franklin Guardian’s existing virtue/constitutional rules operate on plan text and on
/// an internal `QState8` representation with semantic dims. Stochastic prediction rollouts
/// in `uum8d` operate on *normalized amplitude vectors*.
///
/// This adapter therefore enforces constitutional invariants that are valid for amplitude
/// representations:
/// - normalization (Field-of-Truth invariant)
/// - bounded compute (deterministic checks)
/// - entropy floor (prevents variance collapse)
///
/// No synthetic data, no mocks: validation is purely a deterministic function of the state.

#[derive(Debug, Clone)]
pub struct FranklinStochasticOversightConfig {
    /// Normalization tolerance for \( \sum_i amp_i^2 \approx 1 \).
    pub normalization_epsilon: f32,
    /// Minimum Shannon entropy (nats) of probabilities \(p_i = amp_i^2\).
    pub min_entropy_nats: f64,
}

impl Default for FranklinStochasticOversightConfig {
    fn default() -> Self {
        Self {
            normalization_epsilon: 1e-3,
            // Slightly below ln(8)≈2.079 so uniform superposition passes comfortably.
            // This rejects near-collapsed states (variance collapse).
            min_entropy_nats: 1.2,
        }
    }
}

#[derive(Debug, Clone)]
pub struct FranklinStochasticOversight {
    pub config: FranklinStochasticOversightConfig,
}

impl Default for FranklinStochasticOversight {
    fn default() -> Self {
        Self { config: FranklinStochasticOversightConfig::default() }
    }
}

impl FranklinStochasticOversight {
    pub fn new(config: FranklinStochasticOversightConfig) -> Self {
        Self { config }
    }
}

// impl uum8d::ConstitutionalOversight for FranklinStochasticOversight {
impl FranklinStochasticOversight {
    fn validate_state(&self, state: &crate::QState8, step: usize) -> Result<()> {
        // Finite check
        for (i, a) in state.amps.iter().enumerate() {
            if !a.is_finite() {
                return Err(anyhow!("non-finite amp at index {} (step {})", i, step));
            }
        }

        // Normalization check
        if !state.is_normalized(self.config.normalization_epsilon) {
            let norm_sq: f32 = state.amps.iter().map(|a| a * a).sum();
            return Err(anyhow!(
                "QState8 not normalized (step {}): norm_sq={:.6} epsilon={:.6}",
                step,
                norm_sq,
                self.config.normalization_epsilon
            ));
        }

        // Entropy floor check (variance preservation)
        let h = shannon_entropy_nats(state);
        if h < self.config.min_entropy_nats {
            return Err(anyhow!(
                "entropy floor violated (step {}): H_nats={:.6} < min={:.6}",
                step,
                h,
                self.config.min_entropy_nats
            ));
        }

        Ok(())
    }
}

fn shannon_entropy_nats(state: &crate::QState8) -> f64 {
    // H = -Σ p ln p, p = amp^2.
    let mut h = 0.0f64;
    for &a in state.amps.iter() {
        let p = (a as f64) * (a as f64);
        if p > 0.0 {
            h -= p * p.ln();
        }
    }
    h
}

#[cfg(test)]
mod tests {
    use super::*;
    // use uum8d::ConstitutionalOversight;

    #[test]
    fn oversight_accepts_uniform_superposition() -> Result<()> {
        let ov = FranklinStochasticOversight::default();
        let s = uum8d::QState8::from_scores([0.0; 8]); // uniform
        ov.validate_state(&s, 0)?;
        Ok(())
    }

    #[test]
    fn oversight_rejects_entropy_collapse() {
        let ov = FranklinStochasticOversight::default();
        let s = uum8d::QState8::from_scores([100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]); // near-delta
        let err = ov.validate_state(&s, 0).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("entropy floor violated"), "unexpected error: {msg}");
    }
}


