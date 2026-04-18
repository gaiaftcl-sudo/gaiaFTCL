use anyhow::Result;
use ndarray::Array2;

#[derive(Debug, Clone)]
pub struct ForecastStep {
    pub step_index: usize,
    pub valid_time: i64,
    pub predicted_features: Array2<f32>,
    pub uncertainty: Array2<f32>,
}

/// Deterministic baseline forecaster:
/// - persistence model (x_{t+dt} = x_t)
/// - uncertainty remains high unless overridden by validator/learning later.
pub fn baseline_forecast(
    current: &Array2<f32>,
    start_valid_time: i64,
    step_secs: i64,
    steps: usize,
) -> Result<Vec<ForecastStep>> {
    anyhow::ensure!(step_secs > 0, "step_secs must be > 0");
    let mut out = Vec::with_capacity(steps);
    let feature_dim = current.ncols();
    for i in 0..steps {
        let valid_time = start_valid_time + ((i as i64) + 1) * step_secs;
        let predicted = current.clone();
        let uncertainty = Array2::<f32>::from_elem((current.nrows(), feature_dim), 1.0);
        out.push(ForecastStep {
            step_index: i + 1,
            valid_time,
            predicted_features: predicted,
            uncertainty,
        });
    }
    Ok(out)
}


