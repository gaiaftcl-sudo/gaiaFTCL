# Atmosphere Global Ingest - NOAA NOMADS OPeNDAP GFS 0.25 (real data; no synthesis)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/atmosphere_noaa_gfs_opendap_ingest ./services/atmosphere_noaa_gfs_opendap_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/atmosphere_noaa_gfs_opendap_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p atmosphere_noaa_gfs_opendap_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/atmosphere-noaa-gfs-opendap-ingest /app/atmosphere-noaa-gfs-opendap-ingest
ENV RUST_LOG=info
CMD ["/app/atmosphere-noaa-gfs-opendap-ingest"]


