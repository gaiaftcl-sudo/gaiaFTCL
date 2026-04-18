#!/bin/bash
#
# GaiaOS ATC Turbulence Test - Automated Execution Script
#
# Orchestrates:
# 1. Start data service
# 2. Start Tar1090 UI
# 3. Wait for initialization
# 4. Run validation
# 5. Collect results
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SERVICE_DIR="$SCRIPT_DIR/.."

echo "═══════════════════════════════════════════════════════════════"
echo "🚀 GaiaOS ATC Turbulence Visualization Test"
echo "═══════════════════════════════════════════════════════════════"
echo

# ═══════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════

export BIND_ADDR="0.0.0.0:8850"
export ARANGO_URL="http://localhost:8529"
export ARANGO_DB="gaiaos"
export ARANGO_USER="root"
export ARANGO_PASS="openSesame"

TAR1090_PORT=8080
DATA_SERVICE_PID=""
TAR1090_PID=""

# ═══════════════════════════════════════════════════════════════════
# Cleanup Function
# ═══════════════════════════════════════════════════════════════════

cleanup() {
    echo
    echo "🧹 Cleaning up..."
    
    if [ -n "$DATA_SERVICE_PID" ]; then
        echo "   Stopping data service (PID: $DATA_SERVICE_PID)"
        kill $DATA_SERVICE_PID 2>/dev/null || true
    fi
    
    if [ -n "$TAR1090_PID" ]; then
        echo "   Stopping Tar1090 (PID: $TAR1090_PID)"
        kill $TAR1090_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════════════════════════════
# Step 1: Check Prerequisites
# ═══════════════════════════════════════════════════════════════════

echo "📋 Checking prerequisites..."

# Check ArangoDB
if ! curl -s http://localhost:8529/_api/version > /dev/null; then
    echo "❌ ERROR: ArangoDB not running on localhost:8529"
    exit 1
fi
echo "   ✅ ArangoDB running"

# Check aircraft data
AIRCRAFT_COUNT=$(curl -s -u root:openSesame \
    "http://localhost:8529/_db/gaiaos/_api/collection/aircraft_states/count" \
    | jq -r '.count' 2>/dev/null || echo "0")
echo "   ✅ Aircraft in ArangoDB: $AIRCRAFT_COUNT"

if [ "$AIRCRAFT_COUNT" -eq 0 ]; then
    echo "   ⚠️ WARNING: No aircraft data found. Run ingest_aircraft_live.py first."
fi

# Check Python dependencies
if ! python3 -c "import playwright" 2>/dev/null; then
    echo "   ⚠️ Installing Playwright..."
    pip install playwright
    python3 -m playwright install chromium
fi
echo "   ✅ Playwright ready"

# ═══════════════════════════════════════════════════════════════════
# Step 2: Build Data Service
# ═══════════════════════════════════════════════════════════════════

echo
echo "🔨 Building data service..."
cd "$SERVICE_DIR"

if [ ! -f "Cargo.toml" ]; then
    echo "❌ ERROR: Cargo.toml not found in $SERVICE_DIR"
    exit 1
fi

cargo build --release
echo "   ✅ Data service built"

# ═══════════════════════════════════════════════════════════════════
# Step 3: Start Data Service
# ═══════════════════════════════════════════════════════════════════

echo
echo "🚀 Starting data service on port 8850..."
cd "$SERVICE_DIR"
cargo run --release &
DATA_SERVICE_PID=$!
echo "   PID: $DATA_SERVICE_PID"

# Wait for service to be ready
echo "   Waiting for service..."
for i in {1..30}; do
    if curl -s http://localhost:8850/health > /dev/null; then
        echo "   ✅ Data service ready"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo "   ❌ ERROR: Data service did not start"
        exit 1
    fi
done

# ═══════════════════════════════════════════════════════════════════
# Step 4: Start Tar1090 UI
# ═══════════════════════════════════════════════════════════════════

echo
echo "🌐 Starting Tar1090 UI on port $TAR1090_PORT..."

TAR1090_DIR="$SERVICE_DIR/web/tar1090"
if [ ! -d "$TAR1090_DIR" ]; then
    echo "   ⚠️ Tar1090 not found. Using simple HTTP server for now..."
    mkdir -p "$TAR1090_DIR/html"
    
    # Create minimal HTML for testing
    cat > "$TAR1090_DIR/html/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>GaiaOS ATC Turbulence Test</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@v7.5.2/ol.css">
    <script src="https://cdn.jsdelivr.net/npm/ol@v7.5.2/dist/ol.js"></script>
    <style>
        body { margin: 0; padding: 0; }
        #map { width: 100vw; height: 100vh; }
    </style>
</head>
<body>
    <div id="map"></div>
    <script>
        // Initialize OpenLayers map
        var map = new ol.Map({
            target: 'map',
            layers: [
                new ol.layer.Tile({
                    source: new ol.source.OSM()
                })
            ],
            view: new ol.View({
                center: ol.proj.fromLonLat([-75.0, 40.0]),
                zoom: 7
            })
        });
        window.OLMap = map;
    </script>
    <script src="../js/turbulence-overlay.js"></script>
</body>
</html>
EOF
fi

# Start HTTP server
cd "$TAR1090_DIR/html"
python3 -m http.server $TAR1090_PORT &
TAR1090_PID=$!
echo "   PID: $TAR1090_PID"
echo "   ✅ Tar1090 UI started: http://localhost:$TAR1090_PORT"

# Wait for UI to be ready
sleep 3

# ═══════════════════════════════════════════════════════════════════
# Step 5: Run Validation
# ═══════════════════════════════════════════════════════════════════

echo
echo "✅ Running validation tests..."
python3 "$SCRIPT_DIR/validate_atc_turbulence_ui.py"
VALIDATION_RESULT=$?

# ═══════════════════════════════════════════════════════════════════
# Step 6: Results Summary
# ═══════════════════════════════════════════════════════════════════

echo
echo "═══════════════════════════════════════════════════════════════"
if [ $VALIDATION_RESULT -eq 0 ]; then
    echo "✅ TEST PASSED"
else
    echo "❌ TEST FAILED (exit code: $VALIDATION_RESULT)"
fi
echo "═══════════════════════════════════════════════════════════════"
echo
echo "📊 Results:"
echo "   - Data Service: http://localhost:8850"
echo "   - Tar1090 UI: http://localhost:$TAR1090_PORT"
echo "   - Proof Directory: $PROJECT_ROOT/proof/atc_turbulence"
echo

exit $VALIDATION_RESULT

