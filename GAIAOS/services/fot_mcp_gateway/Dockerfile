# FoT-MCP Gateway Dockerfile
# Build context: GAIAOS repository root (see docker-compose.cell.yml).

FROM python:3.12-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY services/fot_mcp_gateway/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/fot_mcp_gateway/main.py services/fot_mcp_gateway/wallet_auth.py services/fot_mcp_gateway/universal_ingest.py ./
COPY services/vie_v2 /app/vie_v2

ENV PYTHONPATH=/app
ENV ARANGO_URL=http://gaiaftcl-arangodb:8529
ENV ARANGO_DB=gaiaos
ENV ARANGO_USER=root
ENV ARANGO_PASSWORD=gaiaftcl2026
ENV NATS_URL=nats://gaiaftcl-nats:4222

EXPOSE 8803

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8803"]
