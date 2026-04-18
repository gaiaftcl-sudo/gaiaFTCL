# GaiaFTCL Cell Updater Service
# Per FTCL-UPDATE-SPEC-1.0 - Closed Update Protocol

FROM python:3.11-slim

# Install Docker CLI for container management
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        ca-certificates && \
    curl -fsSL https://get.docker.com | sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    pydantic \
    httpx

# Copy service code
COPY cell_updater.py main.py

# Data directory for digest sets and keystore
VOLUME /data

# Environment
ENV CELL_ID=gaiaftcl-cell
ENV ARANGO_URL=http://gaiaftcl-arangodb:8529
ENV KEYSTORE_PATH=/data/keystore

EXPOSE 8850

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8850/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8850"]
