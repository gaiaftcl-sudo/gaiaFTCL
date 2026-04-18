# PIREP Ingest Service - Real pilot turbulence reports from NOAA
FROM rust:1.75 as builder
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY services/pirep_ingest ./services/pirep_ingest
RUN cargo build --release -p pirep_ingest

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/pirep-ingest /usr/local/bin/pirep-ingest
CMD ["pirep-ingest"]

