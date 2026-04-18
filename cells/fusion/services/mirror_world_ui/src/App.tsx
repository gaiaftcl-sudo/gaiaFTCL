// GaiaOS Mirror World UI - Main Application Shell
// Zero-Toggle, Pro-Aviation Console with 8D Context Engine
// NO SYNTHETIC DATA. NO SIMULATIONS. LIVE DATA ONLY.

import React, { useState, useEffect } from 'react';
import { MirrorMap } from './components/MirrorMap';
import { InspectorPanel } from './components/InspectorPanel';
import { ConsciousnessStatus } from './components/ConsciousnessStatus';
import { FranklinGuardian } from './components/FranklinGuardian';
import { Dimension, WorldState } from './types/schema';
import { getDimensionInfo } from './hooks/useContextRenderer';
import { fetchLiveWorldState } from './api/liveData';
import './styles/aviation.css';

const DIMENSIONS: Dimension[] = ['truth', 'virtue', 'time', 'space', 'causal', 'social', 'risk', 'economic'];

export default function GaiaOSDashboard() {
	const [dim, setDim] = useState<Dimension>('space');
	const [data, setData] = useState<WorldState | null>(null);
	const [selectedId, setSelectedId] = useState<string | null>(null);
	const [isLive, setIsLive] = useState(true);
	const [connectionStatus, setConnectionStatus] = useState<'connecting' | 'live' | 'error'>('connecting');

	// LIVE DATA LOOP - fetch from real APIs every second
	// NO SYNTHETIC DATA. NO SIMULATIONS.
	useEffect(() => {
		if (!isLive) return;

		// #region agent log
		const logEntry = (location: string, message: string, data: any) => {
			fetch('http://127.0.0.1:7242/ingest/913d4f03-20a5-4003-8a64-18c6bdbc1f0e', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ location, message, data, timestamp: Date.now(), sessionId: 'debug-session', hypothesisId: 'A,B,E' })
			}).catch(() => { });
		};
		// #endregion

		const fetchData = async () => {
			try {
				// #region agent log
				logEntry('App.tsx:fetchData:start', 'Starting data fetch cycle', { isLive });
				// #endregion

				const worldState = await fetchLiveWorldState();
				setData(worldState);

				// #region agent log
				logEntry('App.tsx:fetchData:complete', 'Data fetch cycle complete', {
					flightCount: worldState.flights.length,
					weatherCount: worldState.weather.length,
					alertCount: worldState.alerts.length
				});
				// #endregion

				setConnectionStatus(worldState.flights.length > 0 || worldState.weather.length > 0 ? 'live' : 'connecting');

				// #region agent log
				logEntry('App.tsx:connectionStatus', 'Connection status updated', {
					status: worldState.flights.length > 0 || worldState.weather.length > 0 ? 'live' : 'connecting',
					reason: worldState.flights.length > 0 || worldState.weather.length > 0 ? 'data_received' : 'no_data'
				});
				// #endregion
			} catch (error) {
				console.error('[LIVE] Data fetch failed:', error);
				// #region agent log
				logEntry('App.tsx:fetchData:error', 'Data fetch exception', { error: String(error) });
				// #endregion
				setConnectionStatus('error');
			}
		};

		// Initial load
		// #region agent log
		logEntry('App.tsx:useEffect:init', 'Initializing data fetch loop', { isLive });
		// #endregion
		fetchData();

		// Continuous polling - REAL DATA ONLY
		const interval = setInterval(fetchData, 1000);

		return () => clearInterval(interval);
	}, [isLive]);

	// Keyboard shortcuts
	useEffect(() => {
		const handleKeyDown = (e: KeyboardEvent) => {
			// Number keys 1-8 for dimensions
			if (e.key >= '1' && e.key <= '8') {
				const idx = parseInt(e.key) - 1;
				setDim(DIMENSIONS[idx]);
			}
			// Escape to deselect
			if (e.key === 'Escape') {
				setSelectedId(null);
			}
			// Space to toggle live
			if (e.key === ' ' && e.target === document.body) {
				e.preventDefault();
				setIsLive(prev => !prev);
			}
		};

		window.addEventListener('keydown', handleKeyDown);
		return () => window.removeEventListener('keydown', handleKeyDown);
	}, []);

	const selectedFlight = data?.flights.find(f => f.id === selectedId) || null;
	const dimInfo = getDimensionInfo(dim);

	// Stats
	const activeFlights = data?.flights.filter(f => f.status === 'active').length || 0;
	const emergencies = data?.flights.filter(f => f.status === 'emergency').length || 0;
	const severeWeather = data?.weather.filter(w => w.severity > 0.7).length || 0;

	return (
		<div className="w-screen h-screen flex flex-col bg-[#0b0f19] text-gray-200 overflow-hidden select-none">

			{/* ═══════════════════════════════════════════════════════════════ */}
			{/* TOP NAVIGATION BAR                                              */}
			{/* ═══════════════════════════════════════════════════════════════ */}
			<header className="h-12 border-b border-gray-800 bg-[#080c14] flex items-center px-4 justify-between z-50">

				{/* Left: Branding & Status */}
				<div className="flex items-center gap-4">
					<div className="text-green-500 font-bold tracking-wider text-lg">
						GAIA<span className="text-white">OS</span>
						<span className="text-gray-600 text-xs ml-2">// NODE 0</span>
					</div>
					<div className="h-4 w-[1px] bg-gray-700" />
					<div className="text-xs text-gray-500 font-mono">
						TICK: <span className="text-green-400">{data?.tick || 0}</span>
					</div>
					<div className="h-4 w-[1px] bg-gray-700" />
					<div className="text-xs text-gray-500 font-mono flex items-center gap-4">
						<span>✈️ {activeFlights}</span>
						{emergencies > 0 && (
							<span className="text-red-400 animate-pulse">🚨 {emergencies}</span>
						)}
						{severeWeather > 0 && (
							<span className="text-amber-400">⛈️ {severeWeather}</span>
						)}
					</div>
				</div>

				{/* Center: 8D Dimension Selector */}
				<div className="flex bg-gray-900/50 p-1 rounded-lg border border-gray-800 backdrop-blur">
					{DIMENSIONS.map((d, i) => (
						<button
							key={d}
							onClick={() => setDim(d)}
							title={`${getDimensionInfo(d).label} (${i + 1})`}
							className={`
                px-3 py-1 text-xs font-bold uppercase rounded transition-all duration-200
                ${dim === d
									? 'text-white shadow-lg'
									: 'text-gray-500 hover:text-gray-300 hover:bg-gray-800'}
              `}
							style={{
								backgroundColor: dim === d ? getDimensionInfo(d).color : 'transparent',
								boxShadow: dim === d ? `0 0 20px ${getDimensionInfo(d).color}40` : 'none',
							}}
						>
							D{i + 1}
						</button>
					))}
				</div>

				{/* Right: Live Status */}
				<div className="flex items-center gap-4">
					{/* Connection Status Indicator */}
					<div className={`flex items-center gap-2 px-2 py-1 rounded text-xs font-mono ${connectionStatus === 'live' ? 'bg-green-900/20 text-green-400' :
						connectionStatus === 'error' ? 'bg-red-900/20 text-red-400' :
							'bg-amber-900/20 text-amber-400'
						}`}>
						<div className={`w-2 h-2 rounded-full ${connectionStatus === 'live' ? 'bg-green-500' :
							connectionStatus === 'error' ? 'bg-red-500' :
								'bg-amber-500 animate-pulse'
							}`} />
						{connectionStatus === 'live' ? 'MAINNET' : connectionStatus === 'error' ? 'OFFLINE' : 'SYNC...'}
					</div>
					<button
						onClick={() => setIsLive(prev => !prev)}
						className={`flex items-center gap-2 px-3 py-1 rounded text-xs font-mono transition-all ${isLive
							? 'bg-green-900/30 text-green-400 border border-green-800'
							: 'bg-gray-800 text-gray-500 border border-gray-700'
							}`}
					>
						<div className={`w-2 h-2 rounded-full ${isLive ? 'bg-green-500 animate-pulse' : 'bg-gray-600'}`} />
						{isLive ? 'LIVE' : 'PAUSED'}
					</button>
				</div>
			</header>

			{/* ═══════════════════════════════════════════════════════════════ */}
			{/* MAIN WORKSPACE                                                   */}
			{/* ═══════════════════════════════════════════════════════════════ */}
			<div className="flex-1 relative flex overflow-hidden">

				{/* Left Sidebar: Quick Actions */}
				<div className="w-12 border-r border-gray-800 bg-[#080c14] flex flex-col items-center py-4 gap-3 z-20">
					<SidebarButton icon="🌍" label="World" active />
					<SidebarButton icon="✈️" label="Flights" />
					<SidebarButton icon="🌤️" label="Weather" />
					<div className="flex-1" />
					<SidebarButton icon="⚙️" label="Settings" />
				</div>

				{/* Center: The Map */}
				<div className="flex-1 relative bg-black">
					<MirrorMap
						data={data}
						dimension={dim}
						onSelect={setSelectedId}
						selectedId={selectedId}
					/>

					{/* Radar Sweep Overlay */}
					<div className="absolute inset-0 radar-sweep-overlay pointer-events-none opacity-10" />

					{/* Context Banner Overlay */}
					<div className="absolute top-4 left-4 pointer-events-none">
						<h1
							className="text-5xl font-black uppercase tracking-tighter opacity-10"
							style={{ color: dimInfo.color }}
						>
							{dim}
						</h1>
						<p className="text-xs text-gray-600 mt-1">{dimInfo.description}</p>
					</div>

					{/* Bottom Stats Bar */}
					<div className="absolute bottom-4 left-4 right-4 flex justify-between items-end pointer-events-none">
						<div className="bg-black/60 backdrop-blur px-3 py-2 rounded border border-gray-800">
							<div className="text-xs text-gray-500">Active Lens</div>
							<div className="text-sm font-bold" style={{ color: dimInfo.color }}>
								{dimInfo.label}
							</div>
						</div>

						<div className="text-xs text-gray-600 font-mono">
							Press 1-8 for dimensions • ESC to deselect • SPACE to pause
						</div>
					</div>
				</div>

				{/* Right: Inspector Panel */}
				{selectedId && (
					<div className="w-80 h-full z-30 shadow-2xl">
						<InspectorPanel
							flight={selectedFlight}
							dimension={dim}
							onClose={() => setSelectedId(null)}
						/>
					</div>
				)}

				{/* Consciousness Panels - Fixed Position */}
				<div className="fixed top-20 right-4 w-80 z-40 space-y-4">
					<ConsciousnessStatus />
					<FranklinGuardian />
				</div>
			</div>

			{/* ═══════════════════════════════════════════════════════════════ */}
			{/* BOTTOM: LOGS / TERMINAL                                          */}
			{/* ═══════════════════════════════════════════════════════════════ */}
			<div className="h-28 border-t border-gray-800 bg-[#080c14] font-mono text-xs p-3 overflow-hidden z-40">
				<div className="flex items-center gap-2 mb-2">
					<div className="text-gray-500">SYSTEM LOGS</div>
					<div className="flex-1 h-[1px] bg-gray-800" />
					<div className="text-gray-600">{data?.alerts.length || 0} events</div>
				</div>
				<div className="h-16 overflow-y-auto aviation-scroll space-y-1">
					{data?.alerts.map((alert, i) => (
						<div
							key={i}
							className="text-gray-400 hover:text-gray-200 cursor-pointer transition-colors"
						>
							<span className="text-gray-600">
								[{new Date().toISOString().split('T')[1].split('.')[0]}]
							</span>{' '}
							{alert}
						</div>
					))}
					{(!data?.alerts || data.alerts.length === 0) && (
						<div className="text-gray-600 italic">No alerts</div>
					)}
				</div>
			</div>
		</div>
	);
}

// Sidebar Button Component
const SidebarButton: React.FC<{ icon: string; label: string; active?: boolean }> = ({
	icon, label, active
}) => (
	<button
		title={label}
		className={`
      w-8 h-8 rounded flex items-center justify-center text-sm transition-all
      ${active
				? 'bg-blue-900/30 text-blue-400 border border-blue-800'
				: 'bg-gray-800/50 text-gray-500 hover:text-gray-300 hover:bg-gray-800'}
    `}
	>
		{icon}
	</button>
);

