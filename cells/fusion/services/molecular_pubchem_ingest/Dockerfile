# Molecular PubChem ingest - fetches real 3D records and seeds molecular_tiles
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY services/molecular_pubchem_ingest ./services/molecular_pubchem_ingest

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/molecular_pubchem_ingest",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p molecular_pubchem_ingest

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/molecular-pubchem-ingest /app/molecular-pubchem-ingest
ENV RUST_LOG=info
CMD ["/app/molecular-pubchem-ingest"]


