FROM rust:1.83 as builder
WORKDIR /app
COPY . .
RUN cargo build --workspace --release -p gaiaos_ui

FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/gaiaos_ui /usr/local/bin/gaiaos_ui
RUN mkdir -p ./static ./static/assets

# Copy frontend dist from gaiaos-web
COPY gaiaos-web/dist/index.html ./static/
COPY gaiaos-web/dist/assets/ ./static/assets/

ENV GAIAOS_UI_PORT=3000
ENV GAIAOS_GATEWAY_URL=http://quantum-facade:8900

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["gaiaos_ui"]

