# Multi-stage build for market data ingestion service
FROM rust:1.75 as builder

WORKDIR /app

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY services/entropy_calculation ./services/entropy_calculation
COPY services/market_data_ingest ./services/market_data_ingest

# Build the service
RUN cargo build --release --bin market_data_ingest

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/target/release/market_data_ingest /app/market_data_ingest

# Set environment
ENV RUST_LOG=info

# Run the service
CMD ["/app/market_data_ingest"]

