FROM rust:1.83-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y \
	pkg-config \
	libssl-dev \
	ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

COPY Cargo.toml ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm -rf src

COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
	ca-certificates \
	libssl3 \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/digital-twin /app/digital-twin

RUN useradd -r -s /bin/false gaiaos && \
	chown -R gaiaos:gaiaos /app

USER gaiaos

ENV RUST_LOG=info
ENV BIND_ADDR=0.0.0.0:8770

EXPOSE 8770

CMD ["/app/digital-twin"]

