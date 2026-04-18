# AKG GNN Service - Substrate Geometry Provider
# Multi-stage build for minimal production image

FROM rust:1.88-bookworm AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# Minimal workspace build: avoid stubbing every GaiaOS workspace member.
COPY services/akg_gnn ./services/akg_gnn
COPY services/gaiaos_introspection ./services/gaiaos_introspection

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/akg_gnn",' \
    '  "services/gaiaos_introspection",' \
    ']' \
    > Cargo.toml

# Build release binary
RUN cargo build --release -p akg-gnn

# Runtime stage - minimal image
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary
COPY --from=builder /build/target/release/akg-gnn /app/

# Create model directory
RUN mkdir -p /app/models/all-MiniLM-L6-v2

# Model files will be downloaded at runtime if not present
# Optionally pre-copy during build if available
RUN mkdir -p /app/models/all-MiniLM-L6-v2

# Environment variables
ENV RUST_LOG=info
ENV HOST=0.0.0.0
ENV PORT=8080
ENV ARANGO_URL=http://arangodb:8529
ENV ARANGO_DB=gaiaos
ENV ARANGO_USER=root
ENV ARANGO_PASSWORD=gaiaos
ENV EMBEDDING_MODEL_PATH=/app/models/all-MiniLM-L6-v2

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/akg-gnn"]
