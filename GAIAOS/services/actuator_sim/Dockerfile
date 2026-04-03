FROM rust:1.83-slim-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY crates/ crates/
COPY services/actuator_sim/ services/actuator_sim/
RUN cargo build --release -p actuator_sim

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/actuator-sim /app/actuator-sim
WORKDIR /app
EXPOSE 8032
CMD ["/app/actuator-sim"]
