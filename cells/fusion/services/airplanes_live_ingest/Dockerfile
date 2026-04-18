# GaiaOS Airplanes.live Ingest Service
# FREE global aircraft data, no API key required!

FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY services/airplanes_live_ingest ./services/airplanes_live_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/airplanes_live_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p airplanes_live_ingest

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates curl && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/target/release/airplanes_live_ingest /app/airplanes_live_ingest

ENV RUST_LOG=info

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ps aux | grep airplanes_live_ingest | grep -v grep || exit 1

CMD ["/app/airplanes_live_ingest"]

