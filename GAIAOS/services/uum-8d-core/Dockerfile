# UUM 8D Core Dockerfile
FROM rust:1.83 as builder

WORKDIR /app
COPY services/uum-8d-core/Cargo.toml ./Cargo.toml
COPY services/uum-8d-core/src ./src

RUN cargo build --release

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/uum_8d_core /usr/local/bin/uum_8d_core

ENV RUST_LOG=info

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

CMD ["uum_8d_core"]

