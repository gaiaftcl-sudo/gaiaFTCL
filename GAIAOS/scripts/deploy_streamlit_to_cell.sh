#!/bin/bash
# Deploy Streamlit Dashboards to a single cell

set -euo pipefail

CELL_IP="${1:-77.42.85.60}"
CELL_NAME="${2:-hel1-01}"
SSH_KEY="${3:-~/.ssh/ftclstack-unified}"

echo "🚀 Deploying Streamlit Dashboards to Cell: $CELL_NAME ($CELL_IP)"
echo "=================================================================="

DOMAINS=("quantum" "law" "biology" "atc" "chemistry" "governance" "crypto" "energy" "finance" "logistics" "robotics" "telecom" "climate")

echo "📦 Step 1: Copy Streamlit services to cell..."

ssh -i "$SSH_KEY" "root@${CELL_IP}" "mkdir -p /root/streamlit_services"

for domain in "${DOMAINS[@]}"; do
    echo "  Copying $domain..."
    scp -i "$SSH_KEY" -r "services/discord_streamlit_domains/${domain}" "root@${CELL_IP}:/root/streamlit_services/"
done

echo "  Copying base template..."
scp -i "$SSH_KEY" -r "services/discord_streamlit_base" "root@${CELL_IP}:/root/streamlit_services/"

echo "  Copying journey tracker..."
scp -i "$SSH_KEY" -r "services/discord_journey_tracker" "root@${CELL_IP}:/root/streamlit_services/"

echo ""
echo "🐳 Step 2: Generate docker-compose configuration..."

cat > /tmp/docker-compose.streamlit.yml << 'COMPOSE_EOF'
version: '3.8'

networks:
  gaiaftcl:
    external: true

services:
  streamlit-quantum:
    build: ./streamlit_services/quantum
    container_name: gaiaftcl-streamlit-quantum
    ports:
      - "9001:9001"
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
    build: ./streamlit_services/law
    container_name: gaiaftcl-streamlit-law
    ports:
      - "9002:9002"
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
    build: ./streamlit_services/biology
    container_name: gaiaftcl-streamlit-biology
    ports:
      - "9003:9003"
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
    build: ./streamlit_services/discord_journey_tracker
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

scp -i "$SSH_KEY" /tmp/docker-compose.streamlit.yml "root@${CELL_IP}:/root/docker-compose.streamlit.yml"

echo ""
echo "🏗️  Step 3: Build and start services on cell..."

ssh -i "$SSH_KEY" "root@${CELL_IP}" << 'REMOTE_EOF'
cd /root
echo "Building Streamlit images..."
docker-compose -f docker-compose.streamlit.yml build

echo "Starting Streamlit services..."
docker-compose -f docker-compose.streamlit.yml up -d

echo "Waiting for services to stabilize..."
sleep 10

echo "Service status:"
docker ps | grep streamlit || echo "No Streamlit containers running"
docker ps | grep journey-tracker || echo "Journey tracker not running"
REMOTE_EOF

echo ""
echo "✅ Deployment complete for $CELL_NAME"
echo ""
echo "🔍 Verify deployment:"
echo "  ./scripts/verify_manifold_projection.sh ALL $CELL_IP"
echo ""
