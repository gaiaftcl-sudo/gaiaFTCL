FROM rust:1.85-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev build-essential && rm -rf /var/lib/apt/lists/*
# Copy all services (franklin_guardian depends on gaiaos_introspection)
COPY services/ services/
WORKDIR /build/services/franklin_guardian
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    libssl3 \
    python3 \
    python3-pip \
    python3-venv \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install Playwright and dependencies
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install playwright && \
    /opt/venv/bin/playwright install chromium && \
    /opt/venv/bin/playwright install-deps chromium

WORKDIR /app
COPY --from=builder /build/services/franklin_guardian/target/release/franklin-guardian /app/
COPY services/franklin_guardian/tools/ /app/tools/
RUN chmod +x /app/tools/*.py

# Add venv to PATH so Python scripts can find playwright
ENV PATH="/opt/venv/bin:${PATH}"
ENV RUST_LOG=info
ENV HOST=0.0.0.0
ENV PORT=8803
ENV VCHIP_URL=http://vchip:8001
ENV VIRTUE_ENGINE_URL=http://virtue-engine:8810

EXPOSE 8803
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 CMD curl -f http://localhost:8803/health || exit 1
CMD ["/app/franklin-guardian"]
