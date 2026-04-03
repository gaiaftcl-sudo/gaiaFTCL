# Ocean Global Ingest - NOAA NOMADS OPeNDAP GFSWAVE global 0p25 (real data; no synthesis)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/ocean_noaa_gfswave_opendap_ingest ./services/ocean_noaa_gfswave_opendap_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/ocean_noaa_gfswave_opendap_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p ocean_noaa_gfswave_opendap_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/ocean-noaa-gfswave-opendap-ingest /app/ocean-noaa-gfswave-opendap-ingest
ENV RUST_LOG=info
CMD ["/app/ocean-noaa-gfswave-opendap-ingest"]


