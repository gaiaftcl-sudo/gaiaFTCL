# Atmosphere Global Ingest - Open-Meteo GFS (real model output; no synthesis)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/atmosphere_global_gfs_ingest ./services/atmosphere_global_gfs_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/atmosphere_global_gfs_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p atmosphere_global_gfs_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/atmosphere-global-gfs-ingest /app/atmosphere-global-gfs-ingest
ENV RUST_LOG=info
CMD ["/app/atmosphere-global-gfs-ingest"]


