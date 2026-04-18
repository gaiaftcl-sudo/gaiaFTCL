# GaiaOS ATC Agent Service - Standalone build
FROM rust:1.83-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y pkg-config libssl-dev ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY Cargo.toml ./

# Pin nuid to a version compatible with rand 0.8
RUN mkdir -p src && \
    echo 'fn main() { println!("placeholder"); }' > src/main.rs && \
    cargo build --release 2>&1 || true && \
    rm -rf src

COPY src ./src

# Force nuid to use rand 0.8 compatible version
RUN cargo update -p nuid --precise 0.3.2 2>/dev/null || true && \
    cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates libssl3 curl && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/atc-agent /app/atc-agent

ENV RUST_LOG=info

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ps aux | grep atc-agent | grep -v grep || exit 1

CMD ["/app/atc-agent"]
