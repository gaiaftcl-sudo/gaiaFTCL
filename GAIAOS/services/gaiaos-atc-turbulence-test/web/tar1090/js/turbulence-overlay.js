/**
 * GaiaOS Turbulence Overlay for Tar1090
 * 
 * Adds real-time turbulence field visualization to ATC map
 * - Wind vector arrows
 * - Turbulence intensity heatmap
 * - Risk zone polygons
 */

(function() {
    'use strict';
    
    const API_BASE = 'http://localhost:8850/api';
    const UPDATE_INTERVAL = 1000; // ms
    
    let turbulenceLayer = null;
    let riskZoneLayer = null;
    let windVectorLayer = null;
    let currentField = null;
    
    // ═══════════════════════════════════════════════════════════════════════
    // Initialization
    // ═══════════════════════════════════════════════════════════════════════
    
    function initTurbulenceOverlay() {
        console.log('[Turbulence] Initializing overlay...');
        
        if (typeof OLMap === 'undefined' || !OLMap) {
            console.error('[Turbulence] OpenLayers map not available');
            setTimeout(initTurbulenceOverlay, 1000);
            return;
        }
        
        // Create layers
        createWindVectorLayer();
        createTurbulenceHeatmapLayer();
        createRiskZoneLayer();
        
        // Start update loop
        updateTurbulenceData();
        setInterval(updateTurbulenceData, UPDATE_INTERVAL);
        
        console.log('[Turbulence] Overlay initialized ✅');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Layer Creation
    // ═══════════════════════════════════════════════════════════════════════
    
    function createWindVectorLayer() {
        windVectorLayer = new ol.layer.Vector({
            source: new ol.source.Vector(),
            style: function(feature) {
                const props = feature.getProperties();
                const speed = Math.sqrt(props.u * props.u + props.v * props.v);
                const angle = Math.atan2(props.v, props.u);
                
                return new ol.style.Style({
                    image: new ol.style.RegularShape({
                        points: 3,
                        radius: 8 + speed * 2,
                        rotation: angle,
                        fill: new ol.style.Fill({ 
                            color: getWindSpeedColor(speed) 
                        }),
                        stroke: new ol.style.Stroke({ 
                            color: '#fff', 
                            width: 1 
                        })
                    })
                });
            },
            zIndex: 100
        });
        
        OLMap.addLayer(windVectorLayer);
        console.log('[Turbulence] Wind vector layer created');
    }
    
    function createTurbulenceHeatmapLayer() {
        turbulenceLayer = new ol.layer.Heatmap({
            source: new ol.source.Vector(),
            blur: 20,
            radius: 15,
            weight: function(feature) {
                // Weight by turbulence intensity (k)
                return feature.get('k') / 5.0; // Normalize
            },
            gradient: ['#00f', '#0ff', '#0f0', '#ff0', '#f00'],
            opacity: 0.5,
            zIndex: 50
        });
        
        OLMap.addLayer(turbulenceLayer);
        console.log('[Turbulence] Heatmap layer created');
    }
    
    function createRiskZoneLayer() {
        riskZoneLayer = new ol.layer.Vector({
            source: new ol.source.Vector(),
            style: function(feature) {
                const severity = feature.get('severity');
                return new ol.style.Style({
                    stroke: new ol.style.Stroke({
                        color: getRiskColor(severity),
                        width: 3
                    }),
                    fill: new ol.style.Fill({
                        color: getRiskColor(severity, 0.2)
                    })
                });
            },
            zIndex: 75
        });
        
        OLMap.addLayer(riskZoneLayer);
        console.log('[Turbulence] Risk zone layer created');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Data Fetching & Update
    // ═══════════════════════════════════════════════════════════════════════
    
    async function updateTurbulenceData() {
        try {
            // Get current map bounds
            const extent = OLMap.getView().calculateExtent(OLMap.getSize());
            const [lonMin, latMin, lonMax, latMax] = ol.proj.transformExtent(
                extent, 
                OLMap.getView().getProjection(), 
                'EPSG:4326'
            );
            
            // Fetch turbulence field
            const fieldUrl = `${API_BASE}/turbulence/field?` +
                `lat_min=${latMin}&lat_max=${latMax}&` +
                `lon_min=${lonMin}&lon_max=${lonMax}&` +
                `alt_min=0&alt_max=15000`;
            
            const fieldResp = await fetch(fieldUrl);
            const field = await fieldResp.json();
            currentField = field;
            
            // Update wind vectors
            updateWindVectors(field);
            
            // Update heatmap
            updateTurbulenceHeatmap(field);
            
            // Fetch and update risk zones
            const riskUrl = `${API_BASE}/risk_zones?threshold=0.5`;
            const riskResp = await fetch(riskUrl);
            const riskGeoJSON = await riskResp.json();
            updateRiskZones(riskGeoJSON);
            
        } catch (error) {
            console.error('[Turbulence] Update failed:', error);
        }
    }
    
    function updateWindVectors(field) {
        const source = windVectorLayer.getSource();
        source.clear();
        
        // Sample every Nth cell to avoid clutter
        const sampleRate = 2;
        
        field.grid_data.forEach((cell, idx) => {
            if (idx % sampleRate !== 0) return;
            
            const coords = ol.proj.fromLonLat([cell.lon, cell.lat]);
            const feature = new ol.Feature({
                geometry: new ol.geom.Point(coords),
                u: cell.u,
                v: cell.v,
                k: cell.k
            });
            
            source.addFeature(feature);
        });
        
        console.log(`[Turbulence] Updated ${source.getFeatures().length} wind vectors`);
    }
    
    function updateTurbulenceHeatmap(field) {
        const source = turbulenceLayer.getSource();
        source.clear();
        
        field.grid_data.forEach(cell => {
            if (cell.k < 0.1) return; // Skip low turbulence
            
            const coords = ol.proj.fromLonLat([cell.lon, cell.lat]);
            const feature = new ol.Feature({
                geometry: new ol.geom.Point(coords),
                k: cell.k,
                epsilon: cell.epsilon
            });
            
            source.addFeature(feature);
        });
        
        console.log(`[Turbulence] Updated heatmap with ${source.getFeatures().length} points`);
    }
    
    function updateRiskZones(geoJSON) {
        const source = riskZoneLayer.getSource();
        source.clear();
        
        if (!geoJSON.features || geoJSON.features.length === 0) {
            return;
        }
        
        const format = new ol.format.GeoJSON();
        const features = format.readFeatures(geoJSON, {
            featureProjection: OLMap.getView().getProjection()
        });
        
        features.forEach(feature => {
            feature.setProperties(feature.get('properties') || {});
        });
        
        source.addFeatures(features);
        console.log(`[Turbulence] Updated ${features.length} risk zone(s)`);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Styling Utilities
    // ═══════════════════════════════════════════════════════════════════════
    
    function getWindSpeedColor(speed) {
        // Speed in m/s → color
        if (speed < 2) return 'rgba(0, 255, 0, 0.7)';      // Green: calm
        if (speed < 5) return 'rgba(255, 255, 0, 0.7)';    // Yellow: light
        if (speed < 10) return 'rgba(255, 165, 0, 0.7)';   // Orange: moderate
        return 'rgba(255, 0, 0, 0.7)';                     // Red: strong
    }
    
    function getRiskColor(severity, alpha = 1.0) {
        const colors = {
            'low': [255, 255, 0],       // Yellow
            'moderate': [255, 165, 0],  // Orange
            'high': [255, 69, 0],       // Red-orange
            'severe': [255, 0, 0]       // Red
        };
        
        const rgb = colors[severity] || colors['low'];
        return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha})`;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // UI Controls
    // ═══════════════════════════════════════════════════════════════════════
    
    function addTurbulenceControls() {
        // Add toggle buttons to Tar1090 UI
        const controlDiv = document.createElement('div');
        controlDiv.id = 'turbulence-controls';
        controlDiv.style.cssText = `
            position: absolute;
            top: 10px;
            right: 10px;
            background: rgba(0, 0, 0, 0.8);
            padding: 10px;
            border-radius: 5px;
            z-index: 1000;
        `;
        
        controlDiv.innerHTML = `
            <div style="color: white; font-family: monospace;">
                <h4 style="margin: 0 0 10px 0;">🌪️ Turbulence Overlay</h4>
                <label style="display: block; margin: 5px 0;">
                    <input type="checkbox" id="toggle-wind-vectors" checked>
                    Wind Vectors
                </label>
                <label style="display: block; margin: 5px 0;">
                    <input type="checkbox" id="toggle-heatmap" checked>
                    Turbulence Heatmap
                </label>
                <label style="display: block; margin: 5px 0;">
                    <input type="checkbox" id="toggle-risk-zones" checked>
                    Risk Zones
                </label>
            </div>
        `;
        
        document.body.appendChild(controlDiv);
        
        // Wire up toggles
        document.getElementById('toggle-wind-vectors').addEventListener('change', (e) => {
            windVectorLayer.setVisible(e.target.checked);
        });
        
        document.getElementById('toggle-heatmap').addEventListener('change', (e) => {
            turbulenceLayer.setVisible(e.target.checked);
        });
        
        document.getElementById('toggle-risk-zones').addEventListener('change', (e) => {
            riskZoneLayer.setVisible(e.target.checked);
        });
        
        console.log('[Turbulence] Controls added');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Startup
    // ═══════════════════════════════════════════════════════════════════════
    
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(initTurbulenceOverlay, 2000); // Wait for Tar1090 init
            setTimeout(addTurbulenceControls, 2500);
        });
    } else {
        setTimeout(initTurbulenceOverlay, 2000);
        setTimeout(addTurbulenceControls, 2500);
    }
    
    // Export for external access
    window.GaiaOSTurbulence = {
        getCurrentField: () => currentField,
        refreshNow: updateTurbulenceData
    };
    
    console.log('[Turbulence] Script loaded - waiting for map...');
})();

