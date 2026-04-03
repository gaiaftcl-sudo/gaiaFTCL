use lazy_static::lazy_static;
use prometheus::{Encoder, Histogram, HistogramOpts, IntCounter, Registry, TextEncoder};

lazy_static! {
    pub static ref REGISTRY: Registry = Registry::new();

    pub static ref QFOT_VALIDATION_REQUESTS_TOTAL: IntCounter = IntCounter::new(
        "qfot_validation_requests_total",
        "Total number of QFOT validation requests"
    )
    .unwrap();

    pub static ref QFOT_VALIDATION_PASSES_TOTAL: IntCounter = IntCounter::new(
        "qfot_validation_passes_total",
        "Total number of QFOT validation passes"
    )
    .unwrap();

    pub static ref QFOT_VALIDATION_FAILURES_TOTAL: IntCounter = IntCounter::new(
        "qfot_validation_failures_total",
        "Total number of QFOT validation failures"
    )
    .unwrap();

    pub static ref QFOT_VALIDATION_DURATION_SECONDS: Histogram = Histogram::with_opts(
        HistogramOpts::new(
            "qfot_validation_duration_seconds",
            "Duration of QFOT validation handlers (seconds)"
        )
    )
    .unwrap();
}

pub fn register_metrics() {
    let _ = REGISTRY.register(Box::new(QFOT_VALIDATION_REQUESTS_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(QFOT_VALIDATION_PASSES_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(QFOT_VALIDATION_FAILURES_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(QFOT_VALIDATION_DURATION_SECONDS.clone()));
}

pub fn gather_text() -> String {
    let encoder = TextEncoder::new();
    let metric_families = REGISTRY.gather();
    let mut buffer = Vec::new();
    let _ = encoder.encode(&metric_families, &mut buffer);
    String::from_utf8_lossy(&buffer).to_string()
}


