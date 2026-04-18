# Multi-stage build for cellular physics engine
FROM rust:1.75-slim as builder

WORKDIR /build

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY services/cellular_physics_engine ./services/cellular_physics_engine

# Build the service
RUN cargo build --release -p cellular_physics_engine

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/target/release/cellular_physics_engine /app/

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-8850}/health || exit 1

# Non-root user
RUN useradd -m -u 1000 gaiaos && chown -R gaiaos:gaiaos /app
USER gaiaos

EXPOSE 8850

CMD ["/app/cellular_physics_engine"]

