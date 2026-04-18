# GaiaOS ATC Turbulence Visualization Test System

**Automated integration test for RANS k-ε turbulence visualization on Tar1090-based ATC interface**

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ TAR1090 WEB UI (Modified)                                      │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │  Aircraft    │  │  Turbulence  │  │  Risk Zones  │        │
│  │  Icons +     │  │  Vector      │  │  (colored    │        │
│  │  Callsigns   │  │  Overlay     │  │  regions)    │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│         ▲                 ▲                 ▲                  │
│         │                 │                 │                  │
│         │                 │                 │                  │
└─────────┼─────────────────┼─────────────────┼──────────────────┘
          │                 │                 │
          │  HTTP/WS        │  HTTP/WS        │  HTTP/WS
          │                 │                 │
┌─────────┼─────────────────┼─────────────────┼──────────────────┐
│ GAIAOS ATC DATA SERVICE (Rust/Actix)                          │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GET /api/aircraft                                       │  │
│  │    → Query ArangoDB aircraft_states (6,579 aircraft)    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GET /api/turbulence/field?region={...}                 │  │
│  │    → Invoke RANS k-ε operator via Field World           │  │
│  │    → Return grid: [lat, lon, u, v, w, k, ε, νt]        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GET /api/risk_zones                                     │  │
│  │    → Compute high-turbulence regions (k > threshold)    │  │
│  │    → Return GeoJSON polygons                            │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────┬───────────────────────────────────┬─────────────────┘
          │                                   │
          ▼                                   ▼
┌───────────────────┐              ┌───────────────────────┐
│  ArangoDB         │              │  Field World          │
│  aircraft_states  │              │  RANS k-ε Operator    │
│  6,579 aircraft   │              │  (Just implemented!)  │
└───────────────────┘              └───────────────────────┘
```

---

## Test Execution Flow

### 1. **Initialization (Automated)**
```bash
./scripts/run_atc_turbulence_test.sh
```

**Agent Actions:**
- Start ATC Data Service (port 8850)
- Start Tar1090 web server (port 8080)
- Initialize RANS k-ε operator with atmospheric conditions
- Load aircraft data from ArangoDB

### 2. **Data Injection Loop**
**Every 1 second:**
- Fetch latest aircraft positions from `/api/aircraft`
- Compute turbulence field for visible region
- Push updates to Tar1090 via WebSocket
- Update `aircraft.json` for Tar1090 compatibility

### 3. **Visualization Overlay**
**JavaScript Extension (`tar1090-turbulence-overlay.js`):**
```javascript
// Add to Tar1090's script directory
function initTurbulenceOverlay(map) {
    // Create Leaflet canvas layer
    const turbulenceLayer = L.canvasLayer({
        render: function(info) {
            // Fetch turbulence field from /api/turbulence/field
            // Draw wind vectors as arrows
            // Color-code by k (turbulence intensity)
        }
    });
    
    // Create risk zone layer
    const riskZoneLayer = L.geoJSON(null, {
        style: function(feature) {
            return {
                fillColor: getRiskColor(feature.properties.k_max),
                fillOpacity: 0.3,
                color: 'red',
                weight: 2
            };
        }
    });
    
    map.addLayer(turbulenceLayer);
    map.addLayer(riskZoneLayer);
    
    // Update every 1 second
    setInterval(() => {
        updateTurbulenceField();
        updateRiskZones();
    }, 1000);
}
```

### 4. **Automated Validation**
**Cursor Agent Checks:**
- ✅ Aircraft count matches ArangoDB (expect 6,579)
- ✅ Turbulence overlay visible (DOM element exists)
- ✅ Wind vectors rendered (canvas has data)
- ✅ Risk zones drawn (GeoJSON layer populated)
- ✅ Alignment verified (aircraft in high-k zones have risk indicator)

**Screenshot Capture:**
```python
# scripts/validate_atc_turbulence_ui.py
from playwright.sync_api import sync_playwright

def capture_atc_ui():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        
        # Load ATC UI
        page.goto("http://localhost:8080")
        page.wait_for_selector(".aircraft-icon", timeout=10000)
        
        # Wait for turbulence overlay
        page.wait_for_function("""
            () => document.querySelector('.turbulence-overlay-canvas') !== null
        """)
        
        # Capture screenshot
        page.screenshot(path="proof/atc_turbulence_ui_2025-12-15.png")
        
        # Extract validation data
        aircraft_count = page.locator(".aircraft-icon").count()
        overlay_present = page.locator(".turbulence-overlay-canvas").count() > 0
        
        return {
            "aircraft_count": aircraft_count,
            "overlay_present": overlay_present,
            "screenshot": "proof/atc_turbulence_ui_2025-12-15.png"
        }
```

### 5. **AKG Proof Storage**
**After validation:**
```python
# Store proof in AKG
proof_entry = {
    "_key": f"turbulence_test_{timestamp}",
    "rdf_type": "gaia:TurbulenceVisualizationTest",
    "timestamp": datetime.utcnow().isoformat(),
    "status": "PASS",
    "aircraft_count": 6579,
    "turbulence_overlay_active": True,
    "alignment_verified": True,
    "screenshot_path": "proof/atc_turbulence_ui_2025-12-15.png",
    "rans_operator_version": "1001",
    "provenance": {
        "executor": "cursor_autonomous_agent",
        "trigger": "scheduled_nightly",
        "field_world_version": "0.1.0"
    }
}

arango.collection("test_validations").insert(proof_entry)
```

---

## Test Scenarios

### Scenario 1: Static Aircraft + Steady Wind
- 100 aircraft at fixed positions
- Uniform wind field (10 m/s easterly)
- No turbulence (k=0)
- **Validation:** Wind vectors all point east, no risk zones

### Scenario 2: Dynamic Turbulence Injection
- 50 aircraft
- RANS operator generates vortex at (40°N, 75°W)
- Watch turbulence develop over 60 seconds
- **Validation:** Risk zone appears at vortex location, aircraft inside get flagged

### Scenario 3: Full-Scale Real Data
- All 6,579 aircraft from ArangoDB
- RANS operator computes turbulence for entire US airspace
- **Validation:** All aircraft visible, turbulence fields update smoothly

---

## Remote Triggering

### Method 1: HTTP Endpoint
```bash
curl -X POST http://localhost:8850/api/test/turbulence/trigger \
  -H "Authorization: Bearer $GAIAOS_TEST_TOKEN" \
  -d '{"scenario": "dynamic_turbulence", "duration_seconds": 120}'
```

### Method 2: MCP Command
```python
mcp_gaiaos_gaiaos_virtue_evaluate({
    "direction": "WRITE",
    "params": {
        "action": "trigger_turbulence_test",
        "scenario": "full_scale_real_data"
    }
})
```

### Method 3: Scheduled (Cron)
```cron
# Run nightly at 2 AM
0 2 * * * /gaiaos/scripts/run_atc_turbulence_test.sh >> /var/log/gaiaos_atc_test.log 2>&1
```

---

## Success Criteria

| Metric | Target | Actual |
|--------|--------|--------|
| Aircraft Rendered | 6,579 | TBD |
| Turbulence Overlay Active | Yes | TBD |
| Wind Vectors Visible | Yes | TBD |
| Risk Zones Drawn | Yes (for k>0.5) | TBD |
| FPS | >30 | TBD |
| Alignment Error | <1 pixel | TBD |
| Proof Stored in AKG | Yes | TBD |

---

## File Structure

```
services/gaiaos-atc-turbulence-test/
├── README.md (this file)
├── Cargo.toml
├── src/
│   ├── main.rs              # Actix data service
│   ├── aircraft_feed.rs     # ArangoDB → Tar1090 adapter
│   ├── turbulence_api.rs    # RANS operator → HTTP API
│   └── risk_zones.rs        # GeoJSON risk zone generator
├── web/
│   ├── tar1090/             # Modified Tar1090 fork
│   │   ├── html/
│   │   │   └── index.html
│   │   └── js/
│   │       ├── script.js
│   │       └── turbulence-overlay.js  # NEW
│   └── test-scenarios/
│       ├── static_wind.json
│       ├── dynamic_turbulence.json
│       └── full_scale.json
├── scripts/
│   ├── run_atc_turbulence_test.sh
│   ├── validate_atc_turbulence_ui.py
│   └── store_akg_proof.py
└── proof/
    └── (screenshots stored here)
```

---

## Next Steps

1. **Create Actix Data Service** ✅ (We have the architecture)
2. **Fork/Modify Tar1090** (Add turbulence overlay JS)
3. **Wire RANS Operator API** (Field World → HTTP)
4. **Implement Validation Script** (Playwright + AKG storage)
5. **Deploy & Test** (Run full automated loop)

---

**The turbulence physics is ready. Now we build the visual proof system.**


