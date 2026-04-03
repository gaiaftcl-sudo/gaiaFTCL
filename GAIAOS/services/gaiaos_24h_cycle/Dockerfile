FROM rust:1.83-slim-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY crates/ crates/
COPY services/gaiaos_24h_cycle/ services/gaiaos_24h_cycle/
RUN cargo build --release -p gaiaos_24h_cycle

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/gaiaos-24h-cycle /app/gaiaos-24h-cycle
WORKDIR /app
EXPOSE 8060
CMD ["/app/gaiaos-24h-cycle"]
