use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurbulenceIndicators {
    pub wind_shear_1_per_s: f64,   // |dU/dz| (1/s)
    pub richardson_number: f64,    // Ri stability parameter (dimensionless)
    pub eddy_dissipation_rate: f64, // EDR proxy (m^2/3 s^-1)
    pub turbulence_severity: TurbulenceSeverity,
    pub probability: f64, // 0..1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TurbulenceSeverity {
    None,
    Light,
    Moderate,
    Severe,
    Extreme,
}

#[derive(Debug, Clone)]
pub struct AtmosphereTileLite {
    pub altitude_m: f64,
    pub temperature_k: f64,
    pub wind_u_m_s: f64,
    pub wind_v_m_s: f64,
}

pub fn calculate_turbulence_indicators(upper: &AtmosphereTileLite, lower: &AtmosphereTileLite) -> TurbulenceIndicators {
    let du_dz = calculate_wind_shear(upper, lower);
    let dt_dz = calculate_temperature_gradient(upper, lower);
    let ri = calculate_richardson_number(du_dz, dt_dz, upper.temperature_k);
    let edr = calculate_edr(du_dz, ri);

    let severity = match edr {
        e if e < 0.1 => TurbulenceSeverity::None,
        e if e < 0.3 => TurbulenceSeverity::Light,
        e if e < 0.6 => TurbulenceSeverity::Moderate,
        e if e < 1.0 => TurbulenceSeverity::Severe,
        _ => TurbulenceSeverity::Extreme,
    };

    let probability = calculate_turbulence_probability(ri, edr);

    TurbulenceIndicators {
        wind_shear_1_per_s: du_dz,
        richardson_number: ri,
        eddy_dissipation_rate: edr,
        turbulence_severity: severity,
        probability,
    }
}

fn calculate_wind_shear(upper: &AtmosphereTileLite, lower: &AtmosphereTileLite) -> f64 {
    let dz = (upper.altitude_m - lower.altitude_m).abs();
    if dz < 1.0 {
        return 0.0;
    }
    let u_upper = (upper.wind_u_m_s.powi(2) + upper.wind_v_m_s.powi(2)).sqrt();
    let u_lower = (lower.wind_u_m_s.powi(2) + lower.wind_v_m_s.powi(2)).sqrt();
    (u_upper - u_lower).abs() / dz
}

fn calculate_temperature_gradient(upper: &AtmosphereTileLite, lower: &AtmosphereTileLite) -> f64 {
    let dz = (upper.altitude_m - lower.altitude_m).abs();
    if dz < 1.0 {
        return 0.0;
    }
    (upper.temperature_k - lower.temperature_k) / dz
}

fn calculate_richardson_number(du_dz: f64, dt_dz: f64, temperature_k: f64) -> f64 {
    const G: f64 = 9.81;
    if !temperature_k.is_finite() || temperature_k <= 0.0 {
        return 999.0;
    }
    if du_dz < 1.0e-6 {
        return 999.0;
    }
    (G / temperature_k) * dt_dz / du_dz.powi(2)
}

fn calculate_edr(du_dz: f64, ri: f64) -> f64 {
    let base_edr = du_dz.abs() * 0.1;
    let stability_factor = if ri < 0.25 {
        2.0
    } else if ri < 1.0 {
        1.0
    } else {
        0.1
    };
    base_edr * stability_factor
}

fn calculate_turbulence_probability(ri: f64, edr: f64) -> f64 {
    let ri_prob: f64 = if ri < 0.1 {
        0.95
    } else if ri < 0.25 {
        0.8
    } else if ri < 1.0 {
        0.4
    } else {
        0.05
    };

    let edr_prob: f64 = if edr > 0.6 {
        0.95
    } else if edr > 0.3 {
        0.7
    } else if edr > 0.1 {
        0.4
    } else {
        0.05
    };

    ri_prob.max(edr_prob).clamp(0.0, 1.0)
}


