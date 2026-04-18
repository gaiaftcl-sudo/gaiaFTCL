# GaiaOS Flight Ingest Service
# Production-ready OAuth2 OpenSky integration with 8D prediction

FROM rust:1.83-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source
COPY Cargo.toml .
COPY src/ src/

# Build release binary
RUN cargo build --release

# Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/flight-ingest /usr/local/bin/

# Default environment
ENV RUST_LOG=info
ENV NATS_URL=nats://127.0.0.1:4222
ENV DAILY_CREDIT_LIMIT=4000
ENV PREDICTION_TICK_MS=1000
ENV STALE_THRESHOLD_SECS=300

CMD ["flight-ingest"]

