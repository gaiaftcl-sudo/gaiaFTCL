# GaiaOS Validation Service
# IQ/OQ/PQ Orchestration
# Port: 8802

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
RUN cargo build --release -p gaiaos_validation

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/gaiaos-validation /app/

ENV RUST_LOG=info
ENV HOST=0.0.0.0
ENV PORT=8802

EXPOSE 8802

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8802/health || exit 1

CMD ["/app/gaiaos-validation"]
