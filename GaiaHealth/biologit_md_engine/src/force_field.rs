//! Force Field Parameter Validation
//!
//! Validates MD simulation parameters before PREPARED → RUNNING transition.
//! The WASM constitutional substrate calls force_field_bounds_check() but
//! this native Rust layer provides the same validation for the GxP test suite
//! and for pre-flight checks before WASM invocation.
//!
//! Supported force fields: AMBER, CHARMM (stubs — full implementation in MD engine)

#[derive(Debug, Clone, PartialEq)]
pub enum ForceField {
    Amber,
    Charmm,
    Opls,
    Gromos,
}

#[derive(Debug, Clone)]
pub struct MDParameters {
    pub force_field:       ForceField,
    /// Simulation temperature in Kelvin. Physiological: 300–310 K.
    pub temperature_k:     f64,
    /// Pressure in bar. Physiological: ~1 bar.
    pub pressure_bar:      f64,
    /// Integration timestep in femtoseconds. Typical: 1–4 fs.
    pub timestep_fs:       f64,
    /// Total simulation length in nanoseconds.
    pub simulation_ns:     f64,
    /// Water box padding in Angstroms.
    pub water_padding_ang: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum FFValidationResult {
    Ok,
    TemperatureOutOfRange   { got: f64, min: f64, max: f64 },
    PressureOutOfRange      { got: f64, min: f64, max: f64 },
    TimestepOutOfRange      { got: f64, min: f64, max: f64 },
    SimulationTooShort      { got: f64, min_ns: f64 },
    WaterPaddingInsufficient { got: f64, min_ang: f64 },
}

impl FFValidationResult {
    pub fn is_ok(&self) -> bool { *self == Self::Ok }

    /// Map to WASM FFResult u32: 0 = OK, 1..N = specific fault codes
    pub fn to_ffi_code(&self) -> u32 {
        match self {
            Self::Ok                        => 0,
            Self::TemperatureOutOfRange { .. } => 1,
            Self::PressureOutOfRange { .. }    => 2,
            Self::TimestepOutOfRange { .. }    => 3,
            Self::SimulationTooShort { .. }    => 4,
            Self::WaterPaddingInsufficient { .. } => 5,
        }
    }
}

/// Validate MD parameters against physiologically valid ranges.
///
/// Called before every PREPARED → RUNNING transition.
/// Any failure prevents the transition and triggers a layout mode lock.
pub fn validate_ff_parameters(params: &MDParameters) -> FFValidationResult {
    // Temperature: 250–450 K (physiological window 300–310 K, extended for in vitro)
    if params.temperature_k < 250.0 || params.temperature_k > 450.0 {
        return FFValidationResult::TemperatureOutOfRange {
            got: params.temperature_k, min: 250.0, max: 450.0,
        };
    }

    // Pressure: 0.5–500 bar
    if params.pressure_bar < 0.5 || params.pressure_bar > 500.0 {
        return FFValidationResult::PressureOutOfRange {
            got: params.pressure_bar, min: 0.5, max: 500.0,
        };
    }

    // Timestep: 0.5–4 fs (above 4 fs risks SHAKE constraint failures)
    if params.timestep_fs < 0.5 || params.timestep_fs > 4.0 {
        return FFValidationResult::TimestepOutOfRange {
            got: params.timestep_fs, min: 0.5, max: 4.0,
        };
    }

    // Minimum simulation length: 10 ns (statistical significance)
    if params.simulation_ns < 10.0 {
        return FFValidationResult::SimulationTooShort {
            got: params.simulation_ns, min_ns: 10.0,
        };
    }

    // Water padding: minimum 10 Å
    if params.water_padding_ang < 10.0 {
        return FFValidationResult::WaterPaddingInsufficient {
            got: params.water_padding_ang, min_ang: 10.0,
        };
    }

    FFValidationResult::Ok
}

#[cfg(test)]
mod tests {
    use super::*;

    fn baseline() -> MDParameters {
        MDParameters {
            force_field:       ForceField::Amber,
            temperature_k:     310.0,
            pressure_bar:      1.0,
            timestep_fs:       2.0,
            simulation_ns:     100.0,
            water_padding_ang: 12.0,
        }
    }

    #[test]
    fn tp_009_valid_physiological_params_pass() {
        assert!(validate_ff_parameters(&baseline()).is_ok());
    }

    #[test]
    fn tc_007_temperature_too_high_rejected() {
        let mut p = baseline();
        p.temperature_k = 1000.0;
        assert!(!validate_ff_parameters(&p).is_ok());
    }

    #[test]
    fn tc_008_timestep_too_large_rejected() {
        let mut p = baseline();
        p.timestep_fs = 10.0;
        assert!(!validate_ff_parameters(&p).is_ok());
    }

    #[test]
    fn tc_009_simulation_too_short_rejected() {
        let mut p = baseline();
        p.simulation_ns = 1.0;
        assert!(!validate_ff_parameters(&p).is_ok());
    }
}
