FROM rust:1.85-slim-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY . .
RUN cargo build --release -p uum8d_broker

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl wget && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/uum8d_broker /app/uum8d_broker
WORKDIR /app
EXPOSE 9001
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:9001/health || exit 1
USER 65532:65532
CMD ["/app/uum8d_broker"]


