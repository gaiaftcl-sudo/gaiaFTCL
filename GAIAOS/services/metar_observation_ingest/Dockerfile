# METAR Observation Ingest - offline artifact loader (no network fetch)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/metar_observation_ingest ./services/metar_observation_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/metar_observation_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p metar_observation_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/metar-observation-ingest /app/metar-observation-ingest
ENV RUST_LOG=info
CMD ["/app/metar-observation-ingest"]


