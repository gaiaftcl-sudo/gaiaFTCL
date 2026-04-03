#!/usr/bin/env python3
"""
GaiaOS ATC Training Scenario Generator

Generates synthetic high-risk atmospheric scenarios for:
- Operator training
- System validation
- Stress testing
- Regulatory compliance

Usage:
    export ATC_TURBULENCE_TEST_MODE=training
    ./scripts/generate_training_scenario.py --scenario=severe_turbulence_corridor
"""

import sys
import json
import random
import argparse
from datetime import datetime
from typing import List, Dict, Any
import requests

# Configuration
DATA_SERVICE_URL = "http://localhost:8850"
ARANGO_URL = "http://localhost:8529"
ARANGO_DB = "gaiaos"
ARANGO_USER = "root"
ARANGO_PASS = "openSesame"

# ═══════════════════════════════════════════════════════════════════════════
# Scenario Templates
# ═══════════════════════════════════════════════════════════════════════════

SCENARIOS = {
    "severe_turbulence_corridor": {
        "name": "Severe Turbulence Corridor",
        "description": "High-altitude jet stream with k > 2.0 across major airway",
        "aircraft_count": 20,
        "turbulence_zones": [
            {
                "lat_min": 39.0,
                "lat_max": 41.0,
                "lon_min": -77.0,
                "lon_max": -75.0,
                "k_max": 2.5,
                "severity": "severe"
            }
        ],
        "expected_alerts": 5,
        "expected_reroutes": 3
    },
    
    "stacked_shear_layers": {
        "name": "Stacked Wind Shear Layers",
        "description": "Multiple turbulence layers at different altitudes",
        "aircraft_count": 15,
        "turbulence_zones": [
            {
                "lat_min": 38.0,
                "lat_max": 40.0,
                "lon_min": -78.0,
                "lon_max": -76.0,
                "k_max": 1.8,
                "alt_min": 25000,
                "alt_max": 30000,
                "severity": "high"
            },
            {
                "lat_min": 38.5,
                "lat_max": 39.5,
                "lon_min": -77.5,
                "lon_max": -76.5,
                "k_max": 1.2,
                "alt_min": 35000,
                "alt_max": 40000,
                "severity": "moderate"
            }
        ],
        "expected_alerts": 8,
        "expected_reroutes": 4
    },
    
    "low_altitude_rotor": {
        "name": "Low-Altitude Rotor Zone",
        "description": "Terrain-induced rotor turbulence during approach",
        "aircraft_count": 5,
        "turbulence_zones": [
            {
                "lat_min": 40.5,
                "lat_max": 40.7,
                "lon_min": -74.2,
                "lon_max": -74.0,
                "k_max": 1.5,
                "alt_min": 2000,
                "alt_max": 5000,
                "severity": "high"
            }
        ],
        "expected_alerts": 3,
        "expected_reroutes": 2
    },
    
    "high_density_traffic_turbulence": {
        "name": "High-Density Traffic + Turbulence",
        "description": "Heavy traffic through moderate turbulence zone",
        "aircraft_count": 50,
        "turbulence_zones": [
            {
                "lat_min": 37.0,
                "lat_max": 42.0,
                "lon_min": -80.0,
                "lon_max": -70.0,
                "k_max": 0.9,
                "severity": "moderate"
            }
        ],
        "expected_alerts": 15,
        "expected_reroutes": 8
    },
    
    "clear_air_turbulence_surprise": {
        "name": "Clear-Air Turbulence (Surprise Event)",
        "description": "Sudden turbulence onset with no prior warning",
        "aircraft_count": 10,
        "turbulence_zones": [],  # Injected mid-scenario
        "dynamic_injection": {
            "delay_seconds": 30,
            "zone": {
                "lat_min": 39.5,
                "lat_max": 40.5,
                "lon_min": -76.0,
                "lon_max": -75.0,
                "k_max": 2.0,
                "severity": "severe"
            }
        },
        "expected_alerts": 4,
        "expected_reroutes": 3
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Aircraft Generation
# ═══════════════════════════════════════════════════════════════════════════

def generate_synthetic_aircraft(count: int, region: Dict[str, float]) -> List[Dict[str, Any]]:
    """Generate synthetic aircraft within specified region"""
    aircraft = []
    
    callsigns = ["AAL", "UAL", "DAL", "SWA", "JBU", "ASA", "FFT", "SKW"]
    
    for i in range(count):
        lat = random.uniform(region["lat_min"], region["lat_max"])
        lon = random.uniform(region["lon_min"], region["lon_max"])
        alt = random.randint(25000, 40000)
        
        aircraft.append({
            "hex": f"SYNTH{i:04X}",
            "flight": f"{random.choice(callsigns)}{random.randint(100, 999)}",
            "lat": lat,
            "lon": lon,
            "alt_baro": alt,
            "alt_geom": alt + random.randint(-100, 100),
            "gs": random.uniform(400, 550),
            "track": random.uniform(0, 360),
            "baro_rate": random.randint(-500, 500),
            "category": "A3",  # Jet
            "seen": random.uniform(0.1, 2.0),
            "rssi": -30.0,
            "synthetic": True
        })
    
    return aircraft

# ═══════════════════════════════════════════════════════════════════════════
# Turbulence Zone Injection
# ═══════════════════════════════════════════════════════════════════════════

def inject_turbulence_zones(zones: List[Dict[str, Any]]) -> None:
    """Inject synthetic turbulence zones into ArangoDB"""
    
    for zone in zones:
        zone_doc = {
            "_key": f"synthetic_zone_{datetime.utcnow().timestamp()}",
            "rdf_type": "atc:TurbulenceZone",
            "lat_min": zone["lat_min"],
            "lat_max": zone["lat_max"],
            "lon_min": zone["lon_min"],
            "lon_max": zone["lon_max"],
            "k_max": zone["k_max"],
            "severity": zone["severity"],
            "synthetic": True,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        # Insert into ArangoDB
        url = f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/turbulence_zones"
        resp = requests.post(
            url,
            json=zone_doc,
            auth=(ARANGO_USER, ARANGO_PASS)
        )
        
        if resp.status_code in [201, 202]:
            print(f"   ✅ Injected turbulence zone: {zone['severity']} (k={zone['k_max']})")
        else:
            print(f"   ❌ Failed to inject zone: {resp.status_code}")

# ═══════════════════════════════════════════════════════════════════════════
# Scenario Execution
# ═══════════════════════════════════════════════════════════════════════════

def execute_scenario(scenario_name: str) -> None:
    """Execute a training scenario"""
    
    if scenario_name not in SCENARIOS:
        print(f"❌ Unknown scenario: {scenario_name}")
        print(f"Available: {', '.join(SCENARIOS.keys())}")
        sys.exit(1)
    
    scenario = SCENARIOS[scenario_name]
    
    print("═" * 70)
    print(f"🎯 TRAINING SCENARIO: {scenario['name']}")
    print("═" * 70)
    print(f"Description: {scenario['description']}")
    print(f"Aircraft: {scenario['aircraft_count']}")
    print(f"Turbulence Zones: {len(scenario['turbulence_zones'])}")
    print(f"Expected Alerts: {scenario['expected_alerts']}")
    print(f"Expected Reroutes: {scenario['expected_reroutes']}")
    print()
    
    # Step 1: Create synthetic aircraft
    print("📡 Step 1: Generating synthetic aircraft...")
    
    region = {
        "lat_min": 35.0,
        "lat_max": 45.0,
        "lon_min": -80.0,
        "lon_max": -70.0
    }
    
    aircraft = generate_synthetic_aircraft(scenario['aircraft_count'], region)
    
    # Insert into ArangoDB
    for ac in aircraft:
        doc = {
            "_key": ac["hex"],
            "rdf_type": "atc:AircraftEntity",
            "atc:hasHexCode": ac["hex"],
            "atc:hasCallsign": ac["flight"],
            "geo:lat": ac["lat"],
            "geo:long": ac["lon"],
            "atc:hasBarometricAltitude": ac["alt_baro"],
            "atc:hasGeometricAltitude": ac["alt_geom"],
            "atc:hasGroundSpeed": ac["gs"],
            "atc:hasTrackAngle": ac["track"],
            "atc:hasVerticalRate": ac["baro_rate"],
            "atc:hasAircraftType": ac["category"],
            "atc:hasSeenAgo": ac["seen"],
            "atc:hasRssi": ac["rssi"],
            "synthetic": True,
            "scenario": scenario_name,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        url = f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/aircraft_states"
        requests.post(url, json=doc, auth=(ARANGO_USER, ARANGO_PASS))
    
    print(f"   ✅ Generated {len(aircraft)} synthetic aircraft")
    
    # Step 2: Inject turbulence zones
    print("\n🌪️ Step 2: Injecting turbulence zones...")
    inject_turbulence_zones(scenario['turbulence_zones'])
    
    # Step 3: Wait for system response
    print("\n⏳ Step 3: Running scenario (60 seconds)...")
    print("   Monitoring for:")
    print(f"     • {scenario['expected_alerts']} turbulence alerts")
    print(f"     • {scenario['expected_reroutes']} route replan events")
    
    # Planned: monitor AKG for actual events
    import time
    time.sleep(60)
    
    # Step 4: Collect results
    print("\n📊 Step 4: Collecting results...")
    
    # Query test_validations for scenario results
    query = f"""
    FOR doc IN test_validations
        FILTER doc.scenario == "{scenario_name}"
        SORT doc.timestamp DESC
        LIMIT 1
        RETURN doc
    """
    
    url = f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor"
    resp = requests.post(
        url,
        json={"query": query},
        auth=(ARANGO_USER, ARANGO_PASS)
    )
    
    if resp.status_code == 201:
        results = resp.json().get("result", [])
        if results:
            result = results[0]
            print(f"\n✅ Scenario Results:")
            print(f"   Status: {result.get('status', 'UNKNOWN')}")
            print(f"   Alerts Generated: {result.get('alert_count', 0)}")
            print(f"   Reroutes Triggered: {result.get('reroute_count', 0)}")
        else:
            print("\n⚠️ No results found - validation may still be running")
    
    # Step 5: Cleanup
    print("\n🧹 Step 5: Cleanup (remove synthetic data)...")
    
    # Delete synthetic aircraft
    delete_query = f"""
    FOR doc IN aircraft_states
        FILTER doc.scenario == "{scenario_name}" AND doc.synthetic == true
        REMOVE doc IN aircraft_states
    """
    requests.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": delete_query},
        auth=(ARANGO_USER, ARANGO_PASS)
    )
    
    # Delete synthetic turbulence zones
    delete_zones_query = f"""
    FOR doc IN turbulence_zones
        FILTER doc.synthetic == true
        REMOVE doc IN turbulence_zones
    """
    requests.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": delete_zones_query},
        auth=(ARANGO_USER, ARANGO_PASS)
    )
    
    print("   ✅ Cleanup complete")
    
    print("\n═" * 70)
    print("🎓 TRAINING SCENARIO COMPLETE")
    print("═" * 70)

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Generate ATC training scenarios")
    parser.add_argument(
        "--scenario",
        choices=list(SCENARIOS.keys()),
        default="severe_turbulence_corridor",
        help="Scenario to execute"
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available scenarios"
    )
    
    args = parser.parse_args()
    
    if args.list:
        print("\n📋 Available Training Scenarios:\n")
        for name, scenario in SCENARIOS.items():
            print(f"  • {name}")
            print(f"      {scenario['description']}")
            print()
        sys.exit(0)
    
    execute_scenario(args.scenario)

if __name__ == "__main__":
    main()

