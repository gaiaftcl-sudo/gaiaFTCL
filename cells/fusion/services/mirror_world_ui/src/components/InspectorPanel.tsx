// GaiaOS Mirror World UI - Flight Inspector Panel
// Context-aware detail view that adapts to the active 8D dimension

import React from 'react';
import { Aircraft, Dimension, EightDSignature } from '../types/schema';
import { getDimensionInfo } from '../hooks/useContextRenderer';

interface Props {
	flight: Aircraft | null;
	dimension: Dimension;
	onClose: () => void;
}

export const InspectorPanel: React.FC<Props> = ({ flight, dimension, onClose }) => {
	if (!flight) return null;

	const dimInfo = getDimensionInfo(dimension);

	return (
		<div className="h-full flex flex-col font-mono text-sm bg-gray-900/95 border-l border-gray-800 backdrop-blur panel-slide-in">

			{/* Header */}
			<div className="p-4 border-b border-gray-800 flex justify-between items-center bg-black/40">
				<div>
					<h2 className="text-xl font-bold text-white">{flight.callsign}</h2>
					<div className="text-gray-500 text-xs">{flight.airline} • {flight.type}</div>
					<div className="flex items-center gap-2 mt-1">
						<StatusBadge status={flight.status} />
						<span className="text-xs text-gray-600">ICAO: {flight.id}</span>
					</div>
				</div>
				<button
					onClick={onClose}
					className="text-gray-500 hover:text-white transition-colors p-2"
				>
					✕
				</button>
			</div>

			{/* Flight Strip (Aviation Style) */}
			<div className="p-4 grid grid-cols-3 gap-2 text-center border-b border-gray-800 bg-gray-900">
				<DataCell label="ALT" value={Math.floor(flight.position.alt_ft / 100)} unit="FL" color="emerald" />
				<DataCell label="SPD" value={flight.vector.speed_kts} unit="KTS" color="blue" />
				<DataCell label="HDG" value={`${flight.vector.heading}°`} color="purple" />
			</div>

			{/* 8D Radar Chart */}
			<div className="p-4 border-b border-gray-800">
				<div className="text-xs text-gray-500 mb-2">8D SIGNATURE</div>
				<EightDRadar signature={flight.eightD} activeDimension={dimension} />
			</div>

			{/* Context-Aware Data Block */}
			<div className="flex-1 p-4 overflow-y-auto aviation-scroll">
				<div className="mb-3 flex items-center gap-2">
					<div
						className="w-3 h-3 rounded-full"
						style={{ backgroundColor: dimInfo.color }}
					/>
					<span className="text-xs font-bold text-gray-400 uppercase">
						{dimInfo.label}
					</span>
				</div>
				<div className="text-xs text-gray-600 mb-4">{dimInfo.description}</div>

				<ContextDetails flight={flight} dimension={dimension} />
			</div>

			{/* Metadata */}
			<div className="p-4 border-t border-gray-800 bg-black/20">
				<div className="grid grid-cols-2 gap-2 text-xs">
					<MetaRow label="Passengers" value={flight.metadata.passengers} />
					<MetaRow label="Fuel Flow" value={`${flight.metadata.fuel_flow} kg/h`} />
					<MetaRow label="Squawk" value={flight.squawk} />
					<MetaRow label="Delay" value={`${flight.metadata.delay_minutes} min`} />
				</div>
			</div>

			{/* Footer Actions */}
			<div className="p-4 border-t border-gray-800 flex gap-2">
				<button className="flex-1 bg-blue-900/30 text-blue-400 border border-blue-900 hover:bg-blue-900/50 py-2 px-4 rounded text-xs uppercase font-bold tracking-wider transition-colors">
					Track
				</button>
				<button className="flex-1 bg-red-900/30 text-red-400 border border-red-900 hover:bg-red-900/50 py-2 px-4 rounded text-xs uppercase font-bold tracking-wider transition-colors">
					Alert
				</button>
			</div>
		</div>
	);
};

// Sub-components

const StatusBadge: React.FC<{ status: Aircraft['status'] }> = ({ status }) => {
	const colors = {
		active: 'bg-green-900/50 text-green-400 border-green-800',
		landed: 'bg-gray-900/50 text-gray-400 border-gray-800',
		emergency: 'bg-red-900/50 text-red-400 border-red-800 animate-pulse',
		holding: 'bg-amber-900/50 text-amber-400 border-amber-800',
	};

	return (
		<span className={`px-2 py-0.5 text-xs rounded border ${colors[status]}`}>
			{status.toUpperCase()}
		</span>
	);
};

const DataCell: React.FC<{ label: string; value: number | string; unit?: string; color: string }> = ({
	label, value, unit, color
}) => {
	const colorMap: Record<string, string> = {
		emerald: 'text-emerald-400',
		blue: 'text-blue-400',
		purple: 'text-purple-400',
		amber: 'text-amber-400',
		red: 'text-red-400',
	};

	return (
		<div className="bg-gray-800 p-2 rounded">
			<div className="text-xs text-gray-400">{label}</div>
			<div className={`text-lg ${colorMap[color] || 'text-white'}`}>
				{value}
				{unit && <span className="text-xs text-gray-500 ml-1">{unit}</span>}
			</div>
		</div>
	);
};

const MetaRow: React.FC<{ label: string; value: string | number }> = ({ label, value }) => (
	<div className="flex justify-between">
		<span className="text-gray-500">{label}</span>
		<span className="text-gray-300">{value}</span>
	</div>
);

// Simple 8D Radar visualization (CSS-based)
const EightDRadar: React.FC<{ signature: EightDSignature; activeDimension: Dimension }> = ({
	signature, activeDimension
}) => {
	const dims: Dimension[] = ['truth', 'virtue', 'time', 'space', 'causal', 'social', 'risk', 'economic'];
	const colors: Record<Dimension, string> = {
		truth: '#10b981',
		virtue: '#8b5cf6',
		time: '#3b82f6',
		space: '#06b6d4',
		causal: '#f59e0b',
		social: '#ec4899',
		risk: '#ef4444',
		economic: '#84cc16',
	};

	return (
		<div className="grid grid-cols-4 gap-1">
			{dims.map(dim => (
				<div
					key={dim}
					className={`p-2 rounded text-center transition-all ${dim === activeDimension ? 'bg-gray-700 ring-1 ring-white/20' : 'bg-gray-800'
						}`}
				>
					<div className="text-[10px] text-gray-500 uppercase">{dim.slice(0, 3)}</div>
					<div
						className="text-sm font-bold"
						style={{ color: colors[dim] }}
					>
						{(signature[dim] * 100).toFixed(0)}
					</div>
					{/* Mini bar */}
					<div className="h-1 bg-gray-700 rounded-full mt-1 overflow-hidden">
						<div
							className="h-full rounded-full transition-all"
							style={{
								width: `${signature[dim] * 100}%`,
								backgroundColor: colors[dim]
							}}
						/>
					</div>
				</div>
			))}
		</div>
	);
};

// Context-specific detail blocks
const ContextDetails: React.FC<{ flight: Aircraft; dimension: Dimension }> = ({ flight, dimension }) => {
	switch (dimension) {
		case 'truth':
			return (
				<div className="space-y-2">
					<Row label="Data Confidence" value={`${(flight.eightD.truth * 100).toFixed(0)}%`} />
					<Row label="Last Update" value="2s ago" />
					<Row label="Source" value="ADS-B" />
					<Row label="Verification" value={flight.eightD.truth > 0.9 ? 'Verified' : 'Unverified'}
						alert={flight.eightD.truth < 0.7} />
				</div>
			);

		case 'virtue':
			return (
				<div className="space-y-2">
					<Row label="Compliance" value={`${(flight.eightD.virtue * 100).toFixed(0)}%`}
						alert={flight.eightD.virtue < 0.8} />
					<Row label="Airspace Auth" value="Cleared" />
					<Row label="Route Adherence" value="On Track" />
					<Row label="TCAS Status" value="Normal" />
				</div>
			);

		case 'time':
			return (
				<div className="space-y-2">
					<Row label="ETA" value="14:32 UTC" />
					<Row label="Time Freshness" value={`${(flight.eightD.time * 100).toFixed(0)}%`} />
					<Row label="Prediction Conf" value="High" />
					<Row label="History Points" value={flight.trajectory.length.toString()} />
				</div>
			);

		case 'space':
			return (
				<div className="space-y-2">
					<Row label="Position" value={`${flight.position.lat.toFixed(3)}°, ${flight.position.lon.toFixed(3)}°`} />
					<Row label="Altitude" value={`${flight.position.alt_ft.toLocaleString()} ft`} />
					<Row label="Ground Speed" value={`${flight.vector.speed_kts} kts`} />
					<Row label="Vertical Rate" value={`${flight.vector.vertical_rate > 0 ? '+' : ''}${flight.vector.vertical_rate} fpm`} />
				</div>
			);

		case 'causal':
			return (
				<div className="space-y-2">
					<Row label="Weather Impact" value={`${(flight.eightD.causal * 100).toFixed(0)}%`}
						alert={flight.eightD.causal > 0.5} />
					<Row label="Turbulence" value={flight.metadata.turbulence_index.toFixed(2)}
						alert={flight.metadata.turbulence_index > 0.5} />
					<Row label="Wx Deviation" value="None" />
					<Row label="Reroute Prob" value={flight.eightD.causal > 0.6 ? 'High' : 'Low'} />
				</div>
			);

		case 'social':
			return (
				<div className="space-y-2">
					<Row label="Passengers" value={flight.metadata.passengers.toString()} />
					<Row label="Priority" value={flight.metadata.passengers > 200 ? 'High' : 'Normal'} />
					<Row label="Connections" value="12 pax" />
					<Row label="Special Cargo" value="None" />
				</div>
			);

		case 'risk':
			return (
				<div className="space-y-2">
					<Row label="Risk Score" value={`${(flight.eightD.risk * 100).toFixed(0)}%`}
						alert={flight.eightD.risk > 0.5} />
					<Row label="Separation" value="OK" />
					<Row label="Conflict Prob" value={`${(flight.eightD.risk * 100).toFixed(0)}%`}
						alert={flight.eightD.risk > 0.3} />
					<Row label="TCAS Advisory" value={flight.eightD.risk > 0.7 ? 'TA' : 'None'}
						alert={flight.eightD.risk > 0.7} />
				</div>
			);

		case 'economic':
			return (
				<div className="space-y-2">
					<Row label="Efficiency" value={`${(flight.eightD.economic * 100).toFixed(0)}%`} />
					<Row label="Fuel Flow" value={`${flight.metadata.fuel_flow} kg/h`} />
					<Row label="Cost Index" value="35" />
					<Row label="Delay Cost" value={`$${(flight.metadata.delay_minutes * 50).toLocaleString()}`}
						alert={flight.metadata.delay_minutes > 15} />
				</div>
			);

		default:
			return <div className="text-gray-500 italic">Select a dimension for detailed metrics.</div>;
	}
};

const Row: React.FC<{ label: string; value: string; alert?: boolean }> = ({ label, value, alert }) => (
	<div className="flex justify-between items-center py-1.5 border-b border-gray-800/50 last:border-0">
		<span className="text-gray-400">{label}</span>
		<span className={alert ? "text-red-400 font-bold" : "text-gray-200"}>{value}</span>
	</div>
);

export default InspectorPanel;

