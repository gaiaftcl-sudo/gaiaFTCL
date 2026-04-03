#!/bin/bash
# Start GAIAOS Founder Command Channel

export ARANGO_URL=${ARANGO_URL:-"http://localhost:8529"}
export ARANGO_DB=${ARANGO_DB:-"gaiaos"}
export ARANGO_USER=${ARANGO_USER:-"root"}
export ARANGO_PASSWORD=${ARANGO_PASSWORD:-"gaiaos"}
export NATS_URL=${NATS_URL:-"nats://localhost:4222"}

# Start Backend
echo "Starting Founder Channel Backend on port 8006..."
python3 -m src.app &
BACKEND_PID=$!

# Start UI
echo "Starting Founder Channel UI on port 8005..."
streamlit run src/ui/main.py --server.port 8005 --server.address 0.0.0.0 &
UI_PID=$!

# Start Family Engine
echo "Starting Family Engine..."
python3 -m src.family_engine &
FAMILY_PID=$!

echo "Founder Channel running (Backend: $BACKEND_PID, UI: $UI_PID, Family: $FAMILY_PID)"

trap "kill $BACKEND_PID $UI_PID $FAMILY_PID" EXIT
wait
