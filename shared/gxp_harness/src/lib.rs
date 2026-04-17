//! GxP shared test harness — utilities for GaiaFTCL and GaiaHealth GxP tests.
//! Placeholder — extend as shared test utilities grow.
//! Patents: USPTO 19/460,960 | USPTO 19/096,071

/// Canonical GxP test result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GxpResult {
    Pass,
    Fail(String),
    Skip(String),
}

impl GxpResult {
    pub fn is_pass(&self) -> bool { matches!(self, GxpResult::Pass) }
}
