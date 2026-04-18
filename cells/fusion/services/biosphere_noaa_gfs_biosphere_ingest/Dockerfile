# Biosphere Global Ingest - NOAA NOMADS OPeNDAP GFS biosphere proxies (real data; no synthesis)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/biosphere_noaa_gfs_biosphere_ingest ./services/biosphere_noaa_gfs_biosphere_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/biosphere_noaa_gfs_biosphere_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p biosphere_noaa_gfs_biosphere_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/biosphere-noaa-gfs-biosphere-ingest /app/biosphere-noaa-gfs-biosphere-ingest
ENV RUST_LOG=info
CMD ["/app/biosphere-noaa-gfs-biosphere-ingest"]


