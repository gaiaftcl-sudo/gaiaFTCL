FROM rust:1.85-bookworm AS builder
WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/entropy_api ./services/entropy_api

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/entropy_api",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p entropy_api

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/entropy-api /app/entropy-api
ENV RUST_LOG=info
EXPOSE 8800
CMD ["/app/entropy-api"]


