# GaiaOS ATC Core Service
FROM rust:1.82-bookworm as builder

WORKDIR /app

# Cache dependencies
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

# Build actual service
COPY src ./src
RUN cargo build --release

# Runtime stage
FROM gcr.io/distroless/cc-debian12

COPY --from=builder /app/target/release/gaiaos-atc-core /usr/local/bin/

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/gaiaos-atc-core"]
