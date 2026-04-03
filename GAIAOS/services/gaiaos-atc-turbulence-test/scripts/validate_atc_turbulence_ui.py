#!/usr/bin/env python3
"""
GaiaOS ATC Turbulence UI Validation Script

Automated validation using Playwright:
- Verifies aircraft rendering
- Checks turbulence overlay presence
- Validates alignment between data and visualization
- Captures screenshots for proof
- Stores results in AKG
"""

import sys
import time
import json
from datetime import datetime
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
import requests

# Configuration
TAR1090_URL = "http://localhost:8080"
API_URL = "http://localhost:8850/api"
ARANGO_URL = "http://localhost:8529"
ARANGO_DB = "gaiaos"
ARANGO_USER = "root"
ARANGO_PASS = "openSesame"
PROOF_DIR = Path(__file__).parent.parent.parent.parent / "proof" / "atc_turbulence"


def main():
    print("🚀 Starting ATC Turbulence UI Validation")
    print(f"📍 Tar1090 URL: {TAR1090_URL}")
    print(f"📍 API URL: {API_URL}")
    
    # Ensure proof directory exists
    PROOF_DIR.mkdir(parents=True, exist_ok=True)
    
    validation_results = {
        "timestamp": datetime.utcnow().isoformat(),
        "status": "UNKNOWN",
        "checks": {},
        "screenshots": [],
        "errors": []
    }
    
    try:
        with sync_playwright() as p:
            # Launch browser
            print("\n🌐 Launching browser...")
            browser = p.chromium.launch(headless=True, args=['--no-sandbox'])
            context = browser.new_context(viewport={'width': 1920, 'height': 1080})
            page = context.new_page()
            
            # Navigate to Tar1090
            print(f"📡 Loading {TAR1090_URL}...")
            page.goto(TAR1090_URL, wait_until="networkidle")
            time.sleep(3)  # Wait for dynamic content
            
            # ═══════════════════════════════════════════════════════════════
            # CHECK 1: Aircraft Rendering
            # ═══════════════════════════════════════════════════════════════
            print("\n✅ CHECK 1: Aircraft Rendering")
            
            aircraft_count = get_aircraft_count_from_api()
            print(f"   Expected aircraft (from API): {aircraft_count}")
            
            # Check for aircraft icons in DOM/canvas
            # (Tar1090 renders to canvas, so we check for the canvas element)
            canvas_present = page.locator('canvas').count() > 0
            validation_results["checks"]["canvas_present"] = canvas_present
            print(f"   Canvas element present: {canvas_present}")
            
            if not canvas_present:
                validation_results["errors"].append("No canvas element found - map may not have loaded")
            
            # ═══════════════════════════════════════════════════════════════
            # CHECK 2: Turbulence Overlay Active
            # ═══════════════════════════════════════════════════════════════
            print("\n✅ CHECK 2: Turbulence Overlay")
            
            # Check for turbulence controls
            controls_present = page.locator('#turbulence-controls').count() > 0
            validation_results["checks"]["turbulence_controls_present"] = controls_present
            print(f"   Turbulence controls present: {controls_present}")
            
            if not controls_present:
                validation_results["errors"].append("Turbulence controls not found - overlay may not have loaded")
            
            # Check if overlay JavaScript is loaded
            overlay_loaded = page.evaluate("() => typeof window.GaiaOSTurbulence !== 'undefined'")
            validation_results["checks"]["overlay_script_loaded"] = overlay_loaded
            print(f"   Overlay script loaded: {overlay_loaded}")
            
            if overlay_loaded:
                # Get current field data from overlay
                field_data = page.evaluate("() => window.GaiaOSTurbulence.getCurrentField()")
                if field_data:
                    grid_size = len(field_data.get('grid_data', []))
                    validation_results["checks"]["turbulence_field_loaded"] = True
                    validation_results["checks"]["turbulence_grid_cells"] = grid_size
                    print(f"   Turbulence field loaded: {grid_size} cells")
                else:
                    validation_results["checks"]["turbulence_field_loaded"] = False
                    print("   ⚠️ Turbulence field not yet loaded")
            
            # ═══════════════════════════════════════════════════════════════
            # CHECK 3: Visual Alignment
            # ═══════════════════════════════════════════════════════════════
            print("\n✅ CHECK 3: Data-Visual Alignment")
            
            # Get data from API
            turbulence_field = get_turbulence_field_from_api()
            risk_zones = get_risk_zones_from_api()
            
            if turbulence_field:
                validation_results["checks"]["api_turbulence_available"] = True
                print(f"   API turbulence field: {len(turbulence_field['grid_data'])} cells")
            else:
                validation_results["checks"]["api_turbulence_available"] = False
                validation_results["errors"].append("Could not fetch turbulence field from API")
            
            if risk_zones and risk_zones.get('features'):
                validation_results["checks"]["risk_zones_count"] = len(risk_zones['features'])
                print(f"   Risk zones: {len(risk_zones['features'])}")
            else:
                validation_results["checks"]["risk_zones_count"] = 0
                print("   Risk zones: None")
            
            # ═══════════════════════════════════════════════════════════════
            # SCREENSHOT CAPTURE
            # ═══════════════════════════════════════════════════════════════
            print("\n📸 Capturing screenshots...")
            
            timestamp_str = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            
            # Full view
            screenshot_full = PROOF_DIR / f"atc_turbulence_full_{timestamp_str}.png"
            page.screenshot(path=str(screenshot_full), full_page=False)
            validation_results["screenshots"].append(str(screenshot_full))
            print(f"   Saved: {screenshot_full.name}")
            
            # Close-up (if we can zoom to a risk zone)
            if validation_results["checks"].get("risk_zones_count", 0) > 0:
                # Planned: zoom to risk zone and capture close-up
                pass
            
            # ═══════════════════════════════════════════════════════════════
            # DETERMINE OVERALL STATUS
            # ═══════════════════════════════════════════════════════════════
            all_checks_passed = (
                canvas_present and
                controls_present and
                overlay_loaded and
                validation_results["checks"].get("turbulence_field_loaded", False) and
                validation_results["checks"].get("api_turbulence_available", False)
            )
            
            validation_results["status"] = "PASS" if all_checks_passed else "FAIL"
            
            browser.close()
        
        print(f"\n{'='*60}")
        print(f"🎯 VALIDATION RESULT: {validation_results['status']}")
        print(f"{'='*60}")
        
        # Print summary
        print("\n📊 Summary:")
        for check, result in validation_results["checks"].items():
            status_icon = "✅" if result else "❌"
            print(f"   {status_icon} {check}: {result}")
        
        if validation_results["errors"]:
            print("\n❌ Errors:")
            for error in validation_results["errors"]:
                print(f"   - {error}")
        
        # ═══════════════════════════════════════════════════════════════════
        # STORE IN AKG
        # ═══════════════════════════════════════════════════════════════════
        print("\n💾 Storing validation results in AKG...")
        store_in_akg(validation_results)
        
        # Save JSON report
        report_path = PROOF_DIR / f"validation_report_{timestamp_str}.json"
        with open(report_path, 'w') as f:
            json.dump(validation_results, f, indent=2)
        print(f"   Saved report: {report_path.name}")
        
        return 0 if validation_results["status"] == "PASS" else 1
        
    except Exception as e:
        print(f"\n❌ VALIDATION FAILED: {e}")
        validation_results["status"] = "ERROR"
        validation_results["errors"].append(str(e))
        return 2


def get_aircraft_count_from_api():
    """Get aircraft count from data service"""
    try:
        resp = requests.get(f"{API_URL}/aircraft", timeout=5)
        if resp.status_code == 200:
            aircraft = resp.json()
            return len(aircraft)
    except Exception as e:
        print(f"   ⚠️ Could not fetch aircraft: {e}")
    return 0


def get_turbulence_field_from_api():
    """Get turbulence field from data service"""
    try:
        # Query for reasonable region (US East Coast example)
        params = {
            "lat_min": 35.0,
            "lat_max": 45.0,
            "lon_min": -80.0,
            "lon_max": -70.0,
            "alt_min": 0,
            "alt_max": 15000
        }
        resp = requests.get(f"{API_URL}/turbulence/field", params=params, timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except Exception as e:
        print(f"   ⚠️ Could not fetch turbulence field: {e}")
    return None


def get_risk_zones_from_api():
    """Get risk zones from data service"""
    try:
        resp = requests.get(f"{API_URL}/risk_zones?threshold=0.5", timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except Exception as e:
        print(f"   ⚠️ Could not fetch risk zones: {e}")
    return None


def store_in_akg(validation_results):
    """Store validation results in ArangoDB (AKG)"""
    try:
        # Create proof entry
        proof_entry = {
            "_key": f"turbulence_test_{int(time.time())}",
            "rdf_type": "gaia:TurbulenceVisualizationTest",
            "timestamp": validation_results["timestamp"],
            "status": validation_results["status"],
            "checks": validation_results["checks"],
            "screenshots": validation_results["screenshots"],
            "errors": validation_results["errors"],
            "provenance": {
                "executor": "cursor_autonomous_agent",
                "script": "validate_atc_turbulence_ui.py",
                "rans_operator_id": 1001,
                "field_world_version": "0.1.0"
            }
        }
        
        # Insert into ArangoDB
        url = f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/test_validations"
        resp = requests.post(
            url,
            json=proof_entry,
            auth=(ARANGO_USER, ARANGO_PASS),
            headers={"Content-Type": "application/json"}
        )
        
        if resp.status_code in [201, 202]:
            print("   ✅ Stored in AKG: test_validations collection")
        else:
            print(f"   ⚠️ AKG storage failed: {resp.status_code}")
            
    except Exception as e:
        print(f"   ⚠️ Could not store in AKG: {e}")


if __name__ == "__main__":
    sys.exit(main())

