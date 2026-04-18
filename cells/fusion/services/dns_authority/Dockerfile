# DNS Authority — GoDaddy reconcile + local API (port 8804)
# 1.85+ required: transitive crates (e.g. base64ct) use edition2024 manifests.
FROM rust:1.85-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /src/target/release/dns_authority /app/dns_authority
ENV RUST_LOG=info
EXPOSE 8804
CMD ["/app/dns_authority"]
