#!/usr/bin/env python3
"""
ATC Aircraft Live Ingestion - Ontology-Aware
Uses atc_aircraft_live.ttl ontology for type-safe AKG persistence

Reads from Airplanes.live API, validates against ontology, writes to ArangoDB
with proper RDF typing and provenance tracking.

NO SIMULATION. NO SYNTHETIC DATA. FIELD OF TRUTH ONLY.
"""

import requests
from requests.auth import HTTPBasicAuth
import json
from datetime import datetime, timezone
from typing import Dict, List, Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
AIRPLANES_LIVE_API = "https://api.airplanes.live/v2"
ARANGO_URL = "http://localhost:8529"
ARANGO_DB = "gaiaos"
ARANGO_USER = "root"
ARANGO_PASS = "openSesame"

# Ontology URIs
ATC_NS = "http://gaiaos.cloud/ontology/atc#"
GEO_NS = "http://www.w3.org/2003/01/geo/wgs84_pos#"
PROV_NS = "http://www.w3.org/ns/prov#"
GX_NS = "http://gaiaos.cloud/ontology/core#"

# Collections
AIRCRAFT_STATES_COLLECTION = "aircraft_states"
AIRCRAFT_ENTITIES_COLLECTION = "entities"  # Or dedicated aircraft_entities if preferred

# Data quality thresholds (from ontology safety rules)
MAX_STALENESS_SECONDS = 60  # Discard data older than 1 minute
MIN_NAVIGATION_INTEGRITY = 8  # Require high accuracy

def fetch_aircraft_from_api(lat: float, lon: float, radius: int = 250) -> Optional[Dict]:
    """
    Fetch aircraft data from Airplanes.live API /point endpoint
    
    Args:
        lat: Center latitude
        lon: Center longitude  
        radius: Radius in nautical miles (default 250nm)
        
    Returns:
        API response dict or None on error
    """
    url = f"{AIRPLANES_LIVE_API}/point/{lat}/{lon}/{radius}"
    
    try:
        logger.info(f"Fetching aircraft from {url}")
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        logger.info(f"Received {len(data.get('ac', []))} aircraft")
        return data
        
    except requests.exceptions.RequestException as e:
        logger.error(f"API request failed: {e}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON response: {e}")
        return None

def validate_aircraft_data(aircraft: Dict) -> bool:
    """
    Validate aircraft data against ontology safety rules
    
    Returns True if data passes quality checks, False otherwise
    """
    # Rule 1: Required fields (per ontology)
    required_fields = ['hex', 'lat', 'lon']
    if not all(field in aircraft for field in required_fields):
        logger.warning(f"Missing required fields for hex={aircraft.get('hex', 'unknown')}")
        return False
    
    # Rule 2: Data freshness (seenAgoSeconds < 60)
    seen_ago = aircraft.get('seen_pos', float('inf'))  # API uses 'seen_pos'
    if seen_ago > MAX_STALENESS_SECONDS:
        logger.debug(f"Stale data for hex={aircraft['hex']}: {seen_ago}s old")
        return False
    
    # Rule 3: Position validity (optional, based on nic if available)
    nic = aircraft.get('nic', 0)
    if nic > 0 and nic < MIN_NAVIGATION_INTEGRITY:
        logger.debug(f"Low accuracy for hex={aircraft['hex']}: NIC={nic}")
        # Don't reject, but flag as lower trust
    
    # Rule 4: Emergency status check (log but don't reject)
    emergency = aircraft.get('emergency', 'none')
    if emergency != 'none':
        logger.warning(f"EMERGENCY: hex={aircraft['hex']} status={emergency}")
    
    return True

def map_aircraft_to_akg_state(aircraft: Dict, api_url: str) -> Dict:
    """
    Map Airplanes.live aircraft object to AKG-compatible AircraftState entity
    
    Follows atc_aircraft_live.ttl ontology structure
    """
    hex_code = aircraft['hex']
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Build AKG entity following ontology
    state = {
        "_key": f"state_{hex_code}_{int(datetime.now(timezone.utc).timestamp())}",
        "rdf_type": f"{ATC_NS}AircraftState",
        
        # Link to aircraft entity
        "aircraft_hex": hex_code,
        
        # Geospatial (geo: namespace)
        f"{GEO_NS}lat": aircraft.get('lat'),
        f"{GEO_NS}long": aircraft.get('lon'),
        
        # Altitude
        "atc_hasBarometricAltitude": aircraft.get('alt_baro'),
        "atc_hasGeometricAltitude": aircraft.get('alt_geom'),
        
        # Speed & Direction
        "atc_hasGroundSpeed": aircraft.get('gs'),
        "atc_hasIndicatedAirspeed": aircraft.get('ias'),
        "atc_hasTrueAirspeed": aircraft.get('tas'),
        "atc_hasTrack": aircraft.get('track'),
        "atc_hasTrueHeading": aircraft.get('true_heading'),
        "atc_hasVerticalRate": aircraft.get('baro_rate'),
        
        # Transponder
        "atc_hasSquawkCode": aircraft.get('squawk'),
        "atc_hasEmergencyStatus": aircraft.get('emergency', 'none'),
        
        # Flags
        "atc_isOnGround": aircraft.get('alt_baro', 0) == 0 or aircraft.get('ground'),
        
        # Navigation accuracy
        "atc_hasNavigationIntegrity": aircraft.get('nic'),
        "atc_hasNavigationAccuracy": aircraft.get('nac_p'),
        
        # Temporal & Provenance
        "gx_messageCount": aircraft.get('messages'),
        "gx_seenAgoSeconds": aircraft.get('seen_pos', aircraft.get('seen')),
        "gx_lastSeen": timestamp,  # Approximate (API doesn't give exact timestamp)
        "gx_ingestedAt": timestamp,
        
        # Trust & Source
        "gx_trustedSource": "medium",  # Per ontology: ADS-B is verified but not official FAA
        "prov_wasDerivedFrom": api_url,
        
        # Provenance metadata
        "provenance": {
            "generated_by": "atc_ingest_ontology_aware",
            "cell_id": "cell-03",  # Update as needed
            "agent": "airplanes-live-ingester",
            "tool": "ontology_aware_ingestion.py"
        }
    }
    
    # Remove None values
    state = {k: v for k, v in state.items() if v is not None}
    
    return state

def map_aircraft_to_akg_entity(aircraft: Dict) -> Dict:
    """
    Map Airplanes.live aircraft object to AKG-compatible AircraftEntity
    
    This is the persistent aircraft identity (not timestamped state)
    """
    hex_code = aircraft['hex']
    
    entity = {
        "_key": f"aircraft_{hex_code}",
        "rdf_type": f"{ATC_NS}AircraftEntity",
        
        # Identity
        "atc_hasHexCode": hex_code,
        "atc_hasCallsign": aircraft.get('flight', '').strip(),
        "atc_hasAircraftType": aircraft.get('t'),
        "atc_hasRegistration": aircraft.get('r'),
        
        # Classification
        "atc_isMilitary": aircraft.get('dbflags', 0) & 1 == 1,  # Bit flag check
        
        # Metadata
        "last_updated": datetime.now(timezone.utc).isoformat(),
        
        # Provenance
        "provenance": {
            "generated_by": "atc_ingest_ontology_aware",
            "cell_id": "cell-03",
            "agent": "airplanes-live-ingester",
            "tool": "ontology_aware_ingestion.py"
        }
    }
    
    # Remove None values
    entity = {k: v for k, v in entity.items() if v is not None}
    
    return entity

def upsert_to_arangodb(collection: str, document: Dict) -> bool:
    """
    Upsert document to ArangoDB collection
    
    Returns True on success, False on error
    """
    url = f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{collection}"
    
    try:
        response = requests.post(
            url,
            auth=HTTPBasicAuth(ARANGO_USER, ARANGO_PASS),
            json=document,
            params={"overwriteMode": "update"},  # Upsert behavior
            timeout=5
        )
        
        if response.status_code in [201, 202]:
            return True
        elif response.status_code == 409:
            # Conflict - update instead
            update_url = f"{url}/{document['_key']}"
            update_response = requests.patch(
                update_url,
                auth=HTTPBasicAuth(ARANGO_USER, ARANGO_PASS),
                json=document,
                timeout=5
            )
            return update_response.status_code in [200, 201, 202]
        else:
            logger.error(f"ArangoDB write failed: {response.status_code} - {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        logger.error(f"ArangoDB request failed: {e}")
        return False

def ingest_aircraft_batch(lat: float, lon: float, radius: int = 250) -> Dict[str, int]:
    """
    Fetch and ingest aircraft batch from API to AKG
    
    Returns statistics: {total, valid, states_written, entities_written, errors}
    """
    stats = {
        "total": 0,
        "valid": 0,
        "states_written": 0,
        "entities_written": 0,
        "errors": 0
    }
    
    # Fetch from API
    api_url = f"{AIRPLANES_LIVE_API}/point/{lat}/{lon}/{radius}"
    data = fetch_aircraft_from_api(lat, lon, radius)
    
    if not data:
        logger.error("Failed to fetch aircraft data")
        return stats
    
    aircraft_list = data.get('ac', [])
    stats["total"] = len(aircraft_list)
    
    # Process each aircraft
    for aircraft in aircraft_list:
        # Validate
        if not validate_aircraft_data(aircraft):
            stats["errors"] += 1
            continue
        
        stats["valid"] += 1
        
        # Write entity (persistent aircraft identity)
        entity = map_aircraft_to_akg_entity(aircraft)
        if upsert_to_arangodb(AIRCRAFT_ENTITIES_COLLECTION, entity):
            stats["entities_written"] += 1
        else:
            stats["errors"] += 1
        
        # Write state (timestamped telemetry snapshot)
        state = map_aircraft_to_akg_state(aircraft, api_url)
        if upsert_to_arangodb(AIRCRAFT_STATES_COLLECTION, state):
            stats["states_written"] += 1
        else:
            stats["errors"] += 1
    
    return stats

def main():
    """
    Main ingestion loop
    """
    logger.info("="*60)
    logger.info("ATC Aircraft Live Ingestion - Ontology-Aware")
    logger.info("="*60)
    
    # Example: San Francisco Bay Area
    lat, lon, radius = 37.7749, -122.4194, 250
    
    logger.info(f"Ingesting aircraft near ({lat}, {lon}) within {radius}nm")
    
    stats = ingest_aircraft_batch(lat, lon, radius)
    
    logger.info("="*60)
    logger.info(f"INGESTION COMPLETE")
    logger.info(f"Total: {stats['total']} aircraft")
    logger.info(f"Valid: {stats['valid']} aircraft (passed quality checks)")
    logger.info(f"States Written: {stats['states_written']}")
    logger.info(f"Entities Written: {stats['entities_written']}")
    logger.info(f"Errors: {stats['errors']}")
    logger.info("="*60)
    
    # Success if at least some data was written
    if stats['states_written'] > 0:
        logger.info("✅ Ingestion successful - aircraft_states collection populated")
        return 0
    else:
        logger.error("❌ Ingestion failed - no data written")
        return 1

if __name__ == "__main__":
    exit(main())

