// GaiaOS Mirror World UI - 8D Context Renderer
// The Brain: Translates 8D Context into Visual Style Rules

import { Aircraft, Dimension, WeatherCell } from '../types/schema';

export interface RenderStyle {
	color: string;
	fillOpacity: number;
	strokeOpacity: number;
	showTrail: boolean;
	showLabel: boolean;
	alert: boolean;
	icon: 'target' | 'diamond' | 'triangle';
	scale: number;
}

const PALETTE = {
	SAFE: '#10b981', // Emerald 500
	WARN: '#f59e0b', // Amber 500
	CRIT: '#ef4444', // Red 500
	INFO: '#3b82f6', // Blue 500
	DIM: '#4b5563',  // Gray 600
	WHITE: '#ffffff',
	PURPLE: '#8b5cf6', // Violet 500
	CYAN: '#06b6d4',   // Cyan 500
	PINK: '#ec4899',   // Pink 500
};

export function getFlightStyle(flight: Aircraft, dim: Dimension): RenderStyle {
	const base: RenderStyle = {
		color: PALETTE.SAFE,
		fillOpacity: 1,
		strokeOpacity: 0.8,
		showTrail: false,
		showLabel: true,
		alert: false,
		icon: 'target',
		scale: 1
	};

	// Emergency override - always visible and red
	if (flight.status === 'emergency') {
		base.color = PALETTE.CRIT;
		base.alert = true;
		base.scale = 1.5;
		base.showLabel = true;
		base.icon = 'triangle';
		return base;
	}

	switch (dim) {
		case 'truth': // D1 - Verification/Confidence
			// High verification = Green, Low = Amber/Red
			base.color = flight.eightD.truth > 0.9 ? PALETTE.SAFE :
				flight.eightD.truth > 0.7 ? PALETTE.WARN : PALETTE.CRIT;
			base.fillOpacity = flight.eightD.truth;
			base.showLabel = flight.eightD.truth > 0.5;
			base.icon = flight.eightD.truth > 0.9 ? 'target' : 'diamond';
			break;

		case 'virtue': // D2 - Ethics/Compliance
			// Ethics violations = Red
			base.alert = flight.eightD.virtue < 0.8;
			base.color = base.alert ? PALETTE.CRIT : PALETTE.PURPLE;
			base.icon = base.alert ? 'triangle' : 'diamond';
			base.showTrail = base.alert; // Show path of non-compliant flights
			break;

		case 'time': // D3 - Temporal/Prediction
			// Temporal projection mode
			base.color = PALETTE.INFO;
			base.showTrail = true;
			base.fillOpacity = flight.eightD.time; // Fade stale data
			base.strokeOpacity = 0.6;
			// Dim flights with old data
			if (flight.eightD.time < 0.5) {
				base.color = PALETTE.DIM;
				base.showLabel = false;
			}
			break;

		case 'space': // D4 - Standard ATC View
			// Classic radar display
			base.color = PALETTE.SAFE;
			base.scale = 1.2;
			base.showLabel = true;
			base.icon = 'target';
			// Color by altitude band
			if (flight.position.alt_ft > 35000) base.color = PALETTE.CYAN;
			else if (flight.position.alt_ft > 20000) base.color = PALETTE.INFO;
			else if (flight.position.alt_ft > 10000) base.color = PALETTE.SAFE;
			else base.color = PALETTE.WARN;
			break;

		case 'causal': // D5 - Cause/Effect (Weather Impact)
			// Show causal links (weather impact probability)
			base.color = flight.eightD.causal > 0.6 ? PALETTE.CRIT :
				flight.eightD.causal > 0.4 ? PALETTE.WARN : PALETTE.DIM;
			base.showTrail = true;
			base.alert = flight.eightD.causal > 0.6;
			base.fillOpacity = 0.5 + flight.eightD.causal * 0.5;
			break;

		case 'social': // D6 - Human/Social Priority
			// High Pax = White/Bright
			const isImportant = flight.metadata.passengers > 200;
			base.color = isImportant ? PALETTE.WHITE : PALETTE.DIM;
			base.scale = isImportant ? 1.5 : 0.8;
			base.showLabel = isImportant;
			base.fillOpacity = isImportant ? 1 : 0.4;
			// Holding flights get pink
			if (flight.status === 'holding') base.color = PALETTE.PINK;
			break;

		case 'risk': // D7 - Risk/Safety
			// Risk Heatmap - critical for safety
			base.color = flight.eightD.risk > 0.7 ? PALETTE.CRIT :
				flight.eightD.risk > 0.3 ? PALETTE.WARN : '#065f46';
			base.alert = flight.eightD.risk > 0.7;
			base.showTrail = true; // Show collision vector
			base.scale = 0.8 + flight.eightD.risk * 0.7;
			base.icon = flight.eightD.risk > 0.5 ? 'triangle' : 'target';
			break;

		case 'economic': // D8 - Efficiency/Cost
			// Inefficiency = Amber, Efficient = Green
			base.color = flight.eightD.economic < 0.4 ? PALETTE.CRIT :
				flight.eightD.economic < 0.6 ? PALETTE.WARN : '#059669';
			base.showTrail = flight.metadata.delay_minutes > 15;
			base.fillOpacity = flight.eightD.economic;
			break;
	}

	return base;
}

export interface WeatherStyle {
	visible: boolean;
	color: string;
	opacity: number;
	strokeWidth: number;
	pattern: 'solid' | 'hatched' | 'dotted';
}

export function getWeatherStyle(wx: WeatherCell, dim: Dimension): WeatherStyle {
	// Determine visibility based on dimension context
	const isRisk = dim === 'risk' || dim === 'causal' || dim === 'virtue';
	const isEcon = dim === 'economic';
	const isSpace = dim === 'space';

	let visible = isRisk || (isEcon && wx.severity > 0.5) || isSpace;

	// Specific overrides: Don't show weather in social/truth views
	if (dim === 'social' || dim === 'truth' || dim === 'time') {
		visible = wx.severity > 0.8; // Only show severe weather
	}

	// Weather type colors
	const color = wx.type === 'TURBULENCE' ? '#d946ef' : // Fuchsia
		wx.type === 'STORM' ? '#ef4444' :      // Red
			wx.type === 'ICING' ? '#06b6d4' :      // Cyan
				wx.type === 'WIND_SHEAR' ? '#f97316' : // Orange
					'#6366f1';                             // Indigo (Jetstream)

	// Pattern based on severity
	const pattern = wx.severity > 0.7 ? 'solid' :
		wx.severity > 0.4 ? 'hatched' : 'dotted';

	return {
		visible,
		color,
		opacity: isRisk ? 0.4 + wx.severity * 0.3 : 0.2,
		strokeWidth: wx.severity > 0.5 ? 2 : 1,
		pattern
	};
}

// Utility: Get dimension display info
export function getDimensionInfo(dim: Dimension): { label: string; color: string; description: string } {
	const info: Record<Dimension, { label: string; color: string; description: string }> = {
		truth: { label: 'D1: Truth', color: '#10b981', description: 'Data verification & confidence' },
		virtue: { label: 'D2: Virtue', color: '#8b5cf6', description: 'Ethics & compliance' },
		time: { label: 'D3: Time', color: '#3b82f6', description: 'Temporal projection & freshness' },
		space: { label: 'D4: Space', color: '#06b6d4', description: 'Standard ATC spatial view' },
		causal: { label: 'D5: Causal', color: '#f59e0b', description: 'Cause-effect relationships' },
		social: { label: 'D6: Social', color: '#ec4899', description: 'Human priority & impact' },
		risk: { label: 'D7: Risk', color: '#ef4444', description: 'Safety & collision risk' },
		economic: { label: 'D8: Economic', color: '#84cc16', description: 'Efficiency & cost' },
	};
	return info[dim];
}

