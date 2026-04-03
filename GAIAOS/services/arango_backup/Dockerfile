# Arango Backup Service - scheduled arangodump inside running Arango container
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    tar \
    && rm -rf /var/lib/apt/lists/*

# docker CLI (for docker exec/cp)
RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY services/arango_backup/run_backup.sh /app/run_backup.sh
RUN chmod +x /app/run_backup.sh

ENV RUST_LOG=info
CMD ["/app/run_backup.sh"]


