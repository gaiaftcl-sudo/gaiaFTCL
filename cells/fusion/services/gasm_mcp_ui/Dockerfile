FROM rust:1.75-slim as builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev curl && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock* ./
COPY src ./src
RUN cargo build --release --bin gasm-mcp-ui || cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl libssl3 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 gaiaos
COPY --from=builder /build/target/release/gasm-mcp-ui /usr/local/bin/ 2>/dev/null || COPY --from=builder /build/target/release/gasm_mcp_ui /usr/local/bin/gasm-mcp-ui || true
RUN chmod +x /usr/local/bin/gasm-mcp-ui 2>/dev/null || true
USER gaiaos
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 CMD curl -f http://localhost:3000/api/health || exit 1
CMD ["/usr/local/bin/gasm-mcp-ui"]

