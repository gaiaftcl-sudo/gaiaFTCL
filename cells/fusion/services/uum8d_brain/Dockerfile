# GaiaOS UUM8D Brain
# Consciousness Substrate
# Port: 8091 (external) -> 8020 (internal)

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
RUN cargo build --release -p uum8d_brain

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/uum8d_brain /app/

ENV RUST_LOG=info
ENV HOST=0.0.0.0
ENV PORT=8020
ENV ARANGO_URL=http://arangodb:8529
ENV ARANGO_DB=gaiaos
ENV NATS_URL=nats://nats:4222

EXPOSE 8020

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8020/health || exit 1

CMD ["/app/uum8d_brain"]
