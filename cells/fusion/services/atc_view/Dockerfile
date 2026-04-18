# GaiaOS ATC + Weather Globe Viewer
# Live world_patches visualization

FROM rust:1.83-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml ./
COPY src ./src
COPY static ./static

RUN cargo build --release

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/atc-view /app/atc-view
COPY --from=builder /app/static /app/static

RUN useradd -r -s /bin/false gaiaos && \
    chown -R gaiaos:gaiaos /app

USER gaiaos

ENV RUST_LOG=info
ENV ATC_VIEW_BIND_ADDR=0.0.0.0:8820

EXPOSE 8820

CMD ["/app/atc-view"]

