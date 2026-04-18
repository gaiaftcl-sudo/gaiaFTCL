FROM rustlang/rust:nightly-bookworm AS builder

WORKDIR /build

# Native deps for grib crate optional decoders (openjpeg + libaec)
RUN apt-get update && apt-get install -y --no-install-recommends \
	pkg-config \
	build-essential \
	libopenjp2-7-dev \
	ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

COPY Cargo.toml ./
COPY src ./src

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	libssl3 \
	libopenjp2-7 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/target/release/historical_gfs_backfill /app/historical_gfs_backfill

ENV RUST_LOG=info
CMD ["/app/historical_gfs_backfill"]


