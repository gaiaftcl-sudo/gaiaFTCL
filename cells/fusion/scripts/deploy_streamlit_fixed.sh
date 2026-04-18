#!/bin/bash
set -euo pipefail

CELL_IP="${1:-77.42.85.60}"
CELL_NAME="${2:-hel1-01}"
SSH_KEY="${3:-~/.ssh/ftclstack-unified}"

echo "🚀 Deploying Streamlit to $CELL_NAME ($CELL_IP)"
echo ""

# Create deployment package
echo "📦 Creating deployment package..."
cd /Users/richardgillespie/Documents/FoT8D/GAIAOS

# Copy to cell
echo "📤 Copying files to cell..."
ssh -i "$SSH_KEY" "root@${CELL_IP}" "mkdir -p /root/streamlit_deploy"

# Copy base
scp -i "$SSH_KEY" -r services/discord_streamlit_base "root@${CELL_IP}:/root/streamlit_deploy/"

# Copy domains
scp -i "$SSH_KEY" -r services/discord_streamlit_domains "root@${CELL_IP}:/root/streamlit_deploy/"

# Copy journey tracker
scp -i "$SSH_KEY" -r services/discord_journey_tracker "root@${CELL_IP}:/root/streamlit_deploy/"

echo ""
echo "🐳 Creating docker-compose on cell..."

ssh -i "$SSH_KEY" "root@${CELL_IP}" << 'REMOTE_EOF'
cd /root/streamlit_deploy

cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

networks:
  gaiaftcl:
    external: true

services:
  streamlit-quantum:
    build:
      context: .
      dockerfile: discord_streamlit_domains/quantum/Dockerfile
    container_name: gaiaftcl-streamlit-quantum
    ports:
      - "9001:8501"
    networks:
      - gaiaftcl
    environment:
      - ARANGO_URL=http://gaiaftcl.com:8529
      - ARANGO_DB=gaiaftcl
      - ARANGO_USER=root
      - ARANGO_PASSWORD=gaiaos_akg_secret
      - NATS_URL=nats://gaiaftcl-nats:4222
    restart: unless-stopped

  streamlit-law:
    build:
      context: .
      dockerfile: discord_streamlit_domains/law/Dockerfile
    container_name: gaiaftcl-streamlit-law
    ports:
      - "9002:8501"
    networks:
      - gaiaftcl
    environment:
      - ARANGO_URL=http://gaiaftcl.com:8529
      - ARANGO_DB=gaiaftcl
      - ARANGO_USER=root
      - ARANGO_PASSWORD=gaiaos_akg_secret
      - NATS_URL=nats://gaiaftcl-nats:4222
    restart: unless-stopped

  streamlit-biology:
    build:
      context: .
      dockerfile: discord_streamlit_domains/biology/Dockerfile
    container_name: gaiaftcl-streamlit-biology
    ports:
      - "9003:8501"
    networks:
      - gaiaftcl
    environment:
      - ARANGO_URL=http://gaiaftcl.com:8529
      - ARANGO_DB=gaiaftcl
      - ARANGO_USER=root
      - ARANGO_PASSWORD=gaiaos_akg_secret
      - NATS_URL=nats://gaiaftcl-nats:4222
    restart: unless-stopped

  journey-tracker:
    build:
      context: discord_journey_tracker
    container_name: gaiaftcl-journey-tracker
    networks:
      - gaiaftcl
    environment:
      - ARANGO_URL=http://gaiaftcl.com:8529
      - ARANGO_DB=gaiaftcl
      - ARANGO_USER=root
      - ARANGO_PASSWORD=gaiaos_akg_secret
      - NATS_URL=nats://gaiaftcl-nats:4222
    restart: unless-stopped
COMPOSE_EOF

echo "Building images..."
docker-compose build

echo "Starting services..."
docker-compose up -d

sleep 5

echo "Service status:"
docker ps | grep -E "streamlit|journey" || echo "No services running"
REMOTE_EOF

echo ""
echo "✅ Deployment complete"
