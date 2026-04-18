# GaiaOS Orchestrator Service
# Unified system status and cell health monitoring

FROM rust:1.83-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml ./

RUN mkdir -p src && \
    echo 'fn main() { println!("placeholder"); }' > src/main.rs && \
    cargo build --release && \
    rm -rf src

COPY src ./src

RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/gaiaos-orchestrator /app/gaiaos-orchestrator

RUN useradd -r -s /bin/false gaiaos && \
    chown -R gaiaos:gaiaos /app

USER gaiaos

ENV RUST_LOG=info
ENV ORCH_BIND_ADDR=0.0.0.0:8815

EXPOSE 8815

CMD ["/app/gaiaos-orchestrator"]

