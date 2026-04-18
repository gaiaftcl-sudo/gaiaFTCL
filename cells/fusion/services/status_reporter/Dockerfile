# GaiaOS Status Reporter
# Heartbeat & Metrics Reporting

FROM rust:1.85-bookworm AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy the entire workspace
COPY . .

# Build release binary
RUN cargo build --release -p gaiaos-status-reporter

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/status-reporter /app/

ENV RUST_LOG=info
ENV REPORT_INTERVAL_HOURS=1

CMD ["/app/status-reporter"]

