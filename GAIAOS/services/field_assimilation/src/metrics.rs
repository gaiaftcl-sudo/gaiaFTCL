use lazy_static::lazy_static;
use prometheus::{Encoder, IntCounter, Registry, TextEncoder};

lazy_static! {
    pub static ref REGISTRY: Registry = Registry::new();

    pub static ref ASSIMILATION_CYCLES_TOTAL: IntCounter = IntCounter::new(
        "field_assimilation_cycles_total",
        "Total number of assimilation cycles executed"
    )
    .unwrap();

    pub static ref ATMOSPHERE_TILES_WRITTEN_TOTAL: IntCounter = IntCounter::new(
        "field_assimilation_atmosphere_tiles_written_total",
        "Total number of atmosphere tile documents written"
    )
    .unwrap();

    pub static ref OCEAN_TILES_WRITTEN_TOTAL: IntCounter = IntCounter::new(
        "field_assimilation_ocean_tiles_written_total",
        "Total number of ocean tile documents written"
    )
    .unwrap();

    pub static ref OCEAN_OBSERVATIONS_SEEN_TOTAL: IntCounter = IntCounter::new(
        "field_assimilation_ocean_observations_seen_total",
        "Total number of ocean observations observed during assimilation loops"
    )
    .unwrap();

    pub static ref BIOSPHERE_TILES_WRITTEN_TOTAL: IntCounter = IntCounter::new(
        "field_assimilation_biosphere_tiles_written_total",
        "Total number of biosphere tile documents written"
    )
    .unwrap();

    pub static ref BIOSPHERE_OBSERVATIONS_SEEN_TOTAL: IntCounter = IntCounter::new(
        "field_assimilation_biosphere_observations_seen_total",
        "Total number of biosphere observations observed during assimilation loops"
    )
    .unwrap();
}

pub fn register_metrics() {
    let _ = REGISTRY.register(Box::new(ASSIMILATION_CYCLES_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(ATMOSPHERE_TILES_WRITTEN_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(OCEAN_TILES_WRITTEN_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(OCEAN_OBSERVATIONS_SEEN_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(BIOSPHERE_TILES_WRITTEN_TOTAL.clone()));
    let _ = REGISTRY.register(Box::new(BIOSPHERE_OBSERVATIONS_SEEN_TOTAL.clone()));
}

pub fn gather_text() -> String {
    let encoder = TextEncoder::new();
    let metric_families = REGISTRY.gather();
    let mut buffer = Vec::new();
    let _ = encoder.encode(&metric_families, &mut buffer);
    String::from_utf8_lossy(&buffer).to_string()
}


