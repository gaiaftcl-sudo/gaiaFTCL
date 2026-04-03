# GaiaOS Spatial Gateway
# World Interface Organ - 8D truth field
# Port: 9300 (external) -> 8080 (internal)

FROM rust:1.85-bookworm AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Minimal workspace build
COPY Cargo.lock ./
COPY services/spatial_gateway ./services/spatial_gateway
COPY services/gaiaos_introspection ./services/gaiaos_introspection

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/spatial_gateway",' \
    '  "services/gaiaos_introspection",' \
    ']' \
    > Cargo.toml

# Build release binary
RUN cargo build --release -p spatial_gateway

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/spatial-gateway /app/

ENV RUST_LOG=info
ENV HOST=0.0.0.0
ENV PORT=8080
ENV ARANGO_URL=http://arangodb:8529
ENV ARANGO_DB=gaiaos
ENV NATS_URL=nats://nats:4222

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/spatial-gateway"]
