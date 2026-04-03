// GaiaOS Mirror World UI - 8D Schema Types
// The contract between Rust Unikernel and React UI

export type Dimension = 'truth' | 'virtue' | 'time' | 'space' | 'causal' | 'social' | 'risk' | 'economic';

export interface EightDSignature {
	truth: number;    // 0-1
	virtue: number;   // 0-1
	time: number;     // 0-1
	space: number;    // 0-1
	causal: number;   // 0-1
	social: number;   // 0-1
	risk: number;     // 0-1
	economic: number; // 0-1
}

export interface Aircraft {
	id: string; // ICAO
	callsign: string;
	position: { lat: number; lon: number; alt_ft: number };
	vector: { heading: number; speed_kts: number; vertical_rate: number };
	squawk: string;
	type: string; // e.g., B738
	airline: string;

	// Dynamic State
	trajectory: Array<{ lat: number; lon: number; alt: number; time: number }>;
	status: 'active' | 'landed' | 'emergency' | 'holding';

	// 8D Context
	eightD: EightDSignature;
	metadata: {
		passengers: number;
		fuel_flow: number;
		turbulence_index: number;
		delay_minutes: number;
	};
}

export interface WeatherCell {
	id: string;
	type: 'STORM' | 'TURBULENCE' | 'ICING' | 'WIND_SHEAR' | 'JETSTREAM';
	severity: number; // 0-1
	poly: number[][]; // [[lon, lat], ...]
	altitude_band: [number, number]; // ft
	eightD: EightDSignature;
}

export interface WorldState {
	tick: number;
	flights: Aircraft[];
	weather: WeatherCell[];
	alerts: string[];
}

// API Response types for backend integration
export interface HealthResponse {
	status: string;
	component: string;
	timestamp: string;
}

export interface WorldPatch {
	_key: string;
	context: string;
	center_lat: number;
	center_lon: number;
	vqbit_8d: number[];
	timestamp: string;
	icao24?: string;
	callsign?: string;
	altitude_m?: number;
	velocity_ms?: number;
	heading_deg?: number;
}

