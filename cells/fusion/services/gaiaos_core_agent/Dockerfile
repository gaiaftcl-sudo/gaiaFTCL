# GaiaOS Core Agent
# The central AGI loop orchestrator
# Port: 8804

FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace Cargo files
COPY Cargo.lock ./

# Copy only the crates/services required by gaiaos_core_agent (minimal workspace build)
COPY crates ./crates
COPY services/gaiaos_introspection ./services/gaiaos_introspection
COPY services/gaiaos_core_agent ./services/gaiaos_core_agent

# Create a minimal workspace so Cargo doesn't require unrelated services.
RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/gaiaos_core_agent",' \
    '  "services/gaiaos_introspection",' \
    '  "crates/vchip_client",' \
    '  "crates/gaiaos_substrate",' \
    ']' \
    > Cargo.toml

# Build
RUN cargo build --release -p gaiaos_core_agent

# Runtime
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/gaiaos-core-agent /app/

ENV RUST_LOG=info
ENV GAIA_AGENT_PORT=8804
ENV ARANGO_URL=http://arangodb:8529
ENV SUBSTRATE_URL=http://vchip:8001
ENV VCHIP_URL=http://vchip:8001

EXPOSE 8804

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8804/health || exit 1

CMD ["/app/gaiaos-core-agent"]

