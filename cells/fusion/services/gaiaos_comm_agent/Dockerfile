FROM rust:1.83-slim-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY crates/ crates/
COPY services/gaiaos_comm_agent/ services/gaiaos_comm_agent/
RUN cargo build --release -p gaiaos_comm_agent

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/gaiaos_comm_agent /app/gaiaos_comm_agent
WORKDIR /app
EXPOSE 8041
CMD ["/app/gaiaos_comm_agent"]
