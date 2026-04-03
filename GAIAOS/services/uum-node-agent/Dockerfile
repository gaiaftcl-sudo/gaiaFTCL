# UUM Node Agent Dockerfile
FROM rust:1.83 as builder

WORKDIR /app
COPY services/uum-node-agent/Cargo.toml ./Cargo.toml
COPY services/uum-node-agent/src ./src

RUN cargo build --release

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/uum_node_agent /usr/local/bin/uum_node_agent

ENV RUST_LOG=info

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["uum_node_agent"]

