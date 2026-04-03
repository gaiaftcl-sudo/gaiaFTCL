# GaiaOS ATC Conflict Detector
# Loss of Separation Detection - NO SYNTHETIC DATA

FROM rust:1.85-slim-bookworm AS builder

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Build as part of the workspace (this service depends on workspace crates)
COPY . .

RUN cargo build --release -p atc-conflict

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/target/release/atc-conflict /app/atc-conflict

ENV RUST_LOG=info
ENV NATS_URL=nats://nats:4222
ENV ARANGO_URL=http://arangodb:8529
ENV ARANGO_DB=gaiaos
ENV ARANGO_USER=root
ENV ARANGO_PASSWORD=gaiaos
ENV ARANGO_WORLD_PATCHES_COLLECTION=world_patches

CMD ["/app/atc-conflict"]

