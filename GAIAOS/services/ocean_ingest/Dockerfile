# Ocean Ingest - NOAA NDBC buoy loader (evidence-only; no synthesis)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/ocean_ingest ./services/ocean_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/ocean_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p ocean_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/ocean-ingest /app/ocean-ingest
ENV RUST_LOG=info
CMD ["/app/ocean-ingest"]


