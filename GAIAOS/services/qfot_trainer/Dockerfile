# QFOT Trainer - scheduled gating loop (no mocks; evidence-driven triggers)
FROM rust:1.85-bookworm AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.lock ./
COPY services/qfot_trainer ./services/qfot_trainer

RUN printf '%s\n' \
    '[workspace]' \
    'resolver = "2"' \
    'members = [' \
    '  "services/qfot_trainer",' \
    ']' \
    > Cargo.toml

RUN cargo build --release -p qfot_trainer

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/target/release/qfot-trainer /app/qfot-trainer
ENV RUST_LOG=info
CMD ["/app/qfot-trainer"]


