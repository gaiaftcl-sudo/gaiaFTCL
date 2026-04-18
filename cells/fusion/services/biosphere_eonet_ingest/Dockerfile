FROM rust:1.85-bookworm as builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.lock ./
COPY services/biosphere_eonet_ingest ./services/biosphere_eonet_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/biosphere_eonet_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p biosphere_eonet_ingest

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates libssl3 curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/target/release/biosphere-eonet-ingest /app/biosphere-eonet-ingest

ENV RUST_LOG=info
EXPOSE 8753
CMD ["/app/biosphere-eonet-ingest"]


