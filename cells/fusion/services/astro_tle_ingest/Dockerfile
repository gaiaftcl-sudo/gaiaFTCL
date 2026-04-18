# Astro TLE ingest - pulls real TLEs and writes space_objects + gravitational_tiles
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/astro_tle_ingest ./services/astro_tle_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/astro_tle_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p astro_tle_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/astro-tle-ingest /app/astro-tle-ingest
ENV RUST_LOG=info
CMD ["/app/astro-tle-ingest"]


