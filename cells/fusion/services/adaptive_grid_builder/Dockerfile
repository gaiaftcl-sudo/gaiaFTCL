# Adaptive Grid Builder - generates adaptive_grid_tiles from evidence (airports) + global tiers.
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY crates/airport_registry ./crates/airport_registry
COPY services/adaptive_grid_builder ./services/adaptive_grid_builder

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "crates/airport_registry",' \
    '  "services/adaptive_grid_builder",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p adaptive_grid_builder

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/adaptive-grid-builder /app/adaptive-grid-builder
COPY artifacts/source/ourairports/airports.csv /app/airports.csv
ENV RUST_LOG=info
CMD ["/app/adaptive-grid-builder"]


