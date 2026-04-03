FROM rust:1.85-slim-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY . .
RUN cargo build --release -p gaiaos_comm_router

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/gaiaos_comm_router /app/gaiaos_comm_router
WORKDIR /app
EXPOSE 8040
CMD ["/app/gaiaos_comm_router"]
