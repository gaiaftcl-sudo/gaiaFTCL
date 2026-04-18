# ============================================================================
# GaiaOS Dimensional Viewer - Multi-stage Dockerfile
# ============================================================================
# Builds both the Bevy WASM client and Axum server into a single container
# that serves the UI and provides 8D→3D quantum projection with virtue gating.
#
# Port: 8750
# Dependencies: gaiaos-substrate, gaiaos-franklin-guardian
# ============================================================================

# -------------------------------------------------------
# Stage 1: Build Dimensional Viewer client (Bevy WASM)
# -------------------------------------------------------
# IMPORTANT: client Cargo.toml inherits edition/version from workspace,
# so this stage must build from workspace root and therefore requires
# docker-compose build context = repository root.
FROM rust:1.85-bookworm AS client-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
	pkg-config \
	libssl-dev \
	curl \
	&& rm -rf /var/lib/apt/lists/*

RUN cargo install --locked trunk --version 0.21.14 && \
    rustup target add wasm32-unknown-unknown && \
    cargo install wasm-bindgen-cli --version 0.2.106

WORKDIR /workspace

# Copy full workspace (dimensional-viewer client inherits workspace settings and may rely on
# other workspace members via dependency graph; partial copies break `workspace.*` inheritance).
COPY . .

# Build client to dist/
WORKDIR /workspace/services/dimensional-viewer/client
RUN trunk build --release --public-url /dimensional-viewer/

# -------------------------------------------------------
# Stage 2: Build Dimensional Viewer server (native)
# -------------------------------------------------------
FROM rust:1.85-bookworm AS server-builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
	pkg-config \
	libssl-dev \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /build/server

# Copy server source (this stage is independent of workspace)
COPY services/dimensional-viewer/server/Cargo.toml ./
COPY services/dimensional-viewer/server/src ./src

# Create a dummy Cargo.lock if not present
RUN cargo generate-lockfile

# Build server binary
RUN cargo build --release

# -------------------------------------------------------
# Stage 3: Runtime image
# -------------------------------------------------------
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
	ca-certificates \
	libssl3 \
	curl \
	&& rm -rf /var/lib/apt/lists/*

# Environment configuration
ENV DIMENSIONAL_VIEWER_PORT=8750
ENV SUBSTRATE_URL=http://gaiaos-substrate:8000
ENV FRANKLIN_GUARDIAN_URL=http://gaiaos-franklin-guardian:8803
ENV DEFAULT_VIRTUE_THRESHOLD=0.90
ENV DEFAULT_DIMENSION_MAP=0,2,5
ENV MAX_POINTS_PER_VIEW=10000
ENV DIMENSIONAL_VIEWER_STATIC_DIR=/app/static
ENV RUST_LOG=info

WORKDIR /app

# Copy server binary
COPY --from=server-builder /build/server/target/release/dimensional-viewer /app/dimensional-viewer

# Copy client dist as static assets
COPY --from=client-builder /workspace/services/dimensional-viewer/client/dist /app/static

# Create non-root user
RUN useradd -r -s /bin/false dimensional && \
	chown -R dimensional:dimensional /app

USER dimensional

# Expose HTTP port
EXPOSE 8750

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
	CMD curl -f http://localhost:8750/health || exit 1

# Run server
CMD ["./dimensional-viewer"]
