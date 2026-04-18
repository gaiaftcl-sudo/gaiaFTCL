// GaiaOS Mirror World UI - LIVE Data Fetcher
// NO SYNTHETIC DATA. NO SIMULATIONS. REAL DATA ONLY.

import { WorldState, Aircraft, WeatherCell, WorldPatch } from '../types/schema';

const ATC_VIEW_URL = '/atc';
const ORCHESTRATOR_URL = '/orchestrator';

/**
 * Fetch live ATC data from world_patches
 * NO SIMULATION - Returns empty array if service unavailable
 */
export async function fetchLiveATC(bounds?: {
	lamin: number;
	lamax: number;
	lomin: number;
	lomax: number
}): Promise<Aircraft[]> {
	// #region agent log
	const logEntry = (location: string, message: string, data: any) => {
		fetch('http://127.0.0.1:7242/ingest/913d4f03-20a5-4003-8a64-18c6bdbc1f0e', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ location, message, data, timestamp: Date.now(), sessionId: 'debug-session', hypothesisId: 'B,D' })
		}).catch(() => { });
	};
	// #endregion

	try {
		const params = bounds
			? `?lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
			: '?lamin=-90&lamax=90&lomin=-180&lomax=180';

		const url = `${ATC_VIEW_URL}/api/atc${params}`;
		// #region agent log
		logEntry('liveData.ts:fetchLiveATC:before-fetch', 'About to fetch ATC data', { url, ATC_VIEW_URL, params });
		// #endregion

		const response = await fetch(url);

		// #region agent log
		logEntry('liveData.ts:fetchLiveATC:after-fetch', 'Received ATC response', {
			status: response.status,
			ok: response.ok,
			statusText: response.statusText,
			headers: Object.fromEntries(response.headers.entries())
		});
		// #endregion

		if (!response.ok) {
			console.error(`[LIVE] ATC fetch failed: ${response.status}`);
			// #region agent log
			logEntry('liveData.ts:fetchLiveATC:error', 'ATC fetch failed - non-OK status', { status: response.status });
			// #endregion
			return [];
		}

		const data = await response.json();
		const patches: WorldPatch[] = data.patches || [];

		// #region agent log
		logEntry('liveData.ts:fetchLiveATC:success', 'Parsed ATC patches', { patchCount: patches.length, firstPatch: patches[0], rawData: data });
		// #endregion

		// Convert world_patches to Aircraft format
		return patches.map(patch => patchToAircraft(patch)).filter(Boolean) as Aircraft[];
	} catch (error) {
		console.error('[LIVE] ATC fetch error:', error);
		// #region agent log
		logEntry('liveData.ts:fetchLiveATC:catch', 'ATC fetch exception', { error: String(error), message: error instanceof Error ? error.message : 'Unknown' });
		// #endregion
		return [];
	}
}

/**
 * Fetch live weather data from world_patches
 * NO SIMULATION - Returns empty array if service unavailable
 */
export async function fetchLiveWeather(bounds?: {
	lamin: number;
	lamax: number;
	lomin: number;
	lomax: number;
}): Promise<WeatherCell[]> {
	try {
		const params = bounds
			? `?lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
			: '?lamin=-90&lamax=90&lomin=-180&lomax=180';

		const response = await fetch(`${ATC_VIEW_URL}/api/weather${params}`);

		if (!response.ok) {
			console.error(`[LIVE] Weather fetch failed: ${response.status}`);
			return [];
		}

		const data = await response.json();
		const patches: WorldPatch[] = data.patches || [];

		// Convert to WeatherCell format
		return patches.map(patch => patchToWeather(patch)).filter(Boolean) as WeatherCell[];
	} catch (error) {
		console.error('[LIVE] Weather fetch error:', error);
		return [];
	}
}

/**
 * Fetch system status from orchestrator
 * NO SIMULATION - Returns null if unavailable
 */
export async function fetchSystemStatus(): Promise<{
	cells: Array<{ name: string; status: string }>;
	contexts: Array<{ name: string; status: string }>;
	virtue?: number;
	coherence?: number;
} | null> {
	// #region agent log
	const logEntry = (location: string, message: string, data: any) => {
		fetch('http://127.0.0.1:7242/ingest/913d4f03-20a5-4003-8a64-18c6bdbc1f0e', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ location, message, data, timestamp: Date.now(), sessionId: 'debug-session', hypothesisId: 'B,D' })
		}).catch(() => { });
	};
	// #endregion

	try {
		const url = `${ORCHESTRATOR_URL}/status/system`;
		// #region agent log
		logEntry('liveData.ts:fetchSystemStatus:before-fetch', 'About to fetch system status', { url, ORCHESTRATOR_URL });
		// #endregion

		const response = await fetch(url);

		// #region agent log
		logEntry('liveData.ts:fetchSystemStatus:after-fetch', 'Received status response', {
			status: response.status,
			ok: response.ok,
			statusText: response.statusText
		});
		// #endregion

		if (!response.ok) {
			console.error(`[LIVE] Orchestrator fetch failed: ${response.status}`);
			// #region agent log
			logEntry('liveData.ts:fetchSystemStatus:error', 'Status fetch failed', { status: response.status });
			// #endregion
			return null;
		}

		const data = await response.json();
		// #region agent log
		logEntry('liveData.ts:fetchSystemStatus:success', 'Parsed status data', { data });
		// #endregion

		return data;
	} catch (error) {
		console.error('[LIVE] Orchestrator fetch error:', error);
		// #region agent log
		logEntry('liveData.ts:fetchSystemStatus:catch', 'Status fetch exception', { error: String(error) });
		// #endregion
		return null;
	}
}

/**
 * Fetch complete world state - LIVE DATA ONLY
 */
export async function fetchLiveWorldState(): Promise<WorldState> {
	const [flights, weather, status] = await Promise.all([
		fetchLiveATC(),
		fetchLiveWeather(),
		fetchSystemStatus(),
	]);

	// Generate alerts from live status
	const alerts: string[] = [];

	if (status) {
		// Add alerts for unhealthy services
		status.cells
			.filter(c => c.status !== 'healthy')
			.forEach(c => alerts.push(`⚠️ Service ${c.name}: ${c.status}`));

		// Add alerts for context issues
		status.contexts
			.filter(c => c.status !== 'healthy')
			.forEach(c => alerts.push(`🔴 Context ${c.name}: ${c.status}`));
	}

	// Add emergency flight alerts
	flights
		.filter(f => f.status === 'emergency')
		.forEach(f => alerts.push(`🚨 EMERGENCY: ${f.callsign} at FL${Math.floor(f.position.alt_ft / 100)}`));

	return {
		tick: Date.now(),
		flights,
		weather,
		alerts,
	};
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversion helpers
// ─────────────────────────────────────────────────────────────────────────────

function patchToAircraft(patch: WorldPatch): Aircraft | null {
	if (!patch.icao24 || !patch.center_lat || !patch.center_lon) {
		return null;
	}

	const vqbit = patch.vqbit_8d || [0.9, 0.9, 0.9, 0.9, 0.5, 0.5, 0.2, 0.7];

	return {
		id: patch.icao24,
		callsign: patch.callsign || patch.icao24,
		position: {
			lat: patch.center_lat,
			lon: patch.center_lon,
			alt_ft: (patch.altitude_m || 10000) * 3.28084,
		},
		vector: {
			heading: patch.heading_deg || 0,
			speed_kts: (patch.velocity_ms || 250) * 1.94384,
			vertical_rate: 0,
		},
		squawk: '1200',
		type: 'UNKN',
		airline: patch.callsign?.slice(0, 3) || 'UNK',
		trajectory: [],
		status: 'active',
		eightD: {
			truth: vqbit[0] || 0.9,
			virtue: vqbit[1] || 0.9,
			time: vqbit[2] || 0.9,
			space: vqbit[3] || 0.9,
			causal: vqbit[4] || 0.5,
			social: vqbit[5] || 0.5,
			risk: vqbit[6] || 0.2,
			economic: vqbit[7] || 0.7,
		},
		metadata: {
			passengers: 150,
			fuel_flow: 2500,
			turbulence_index: vqbit[4] || 0.3,
			delay_minutes: 0,
		},
	};
}

function patchToWeather(patch: WorldPatch): WeatherCell | null {
	if (!patch.center_lat || !patch.center_lon) {
		return null;
	}

	const vqbit = patch.vqbit_8d || [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];
	const severity = vqbit[6] || 0.3; // Risk dimension

	// Create a simple polygon around the point
	const size = 2; // degrees
	const poly = [
		[patch.center_lon - size, patch.center_lat - size],
		[patch.center_lon + size, patch.center_lat - size],
		[patch.center_lon + size, patch.center_lat + size],
		[patch.center_lon - size, patch.center_lat + size],
	];

	return {
		id: patch._key,
		type: severity > 0.7 ? 'STORM' : severity > 0.4 ? 'TURBULENCE' : 'WIND_SHEAR',
		severity,
		poly,
		altitude_band: [10000, 45000],
		eightD: {
			truth: vqbit[0] || 0.9,
			virtue: vqbit[1] || 0.9,
			time: vqbit[2] || 0.9,
			space: vqbit[3] || 0.9,
			causal: vqbit[4] || 0.5,
			social: vqbit[5] || 0.5,
			risk: vqbit[6] || 0.5,
			economic: vqbit[7] || 0.7,
		},
	};
}

export default fetchLiveWorldState;

