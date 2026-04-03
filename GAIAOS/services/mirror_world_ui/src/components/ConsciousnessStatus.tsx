import { useEffect, useState } from 'react';

interface ConsciousnessState {
	service: string;
	status: string;
	role: string;
	arango_connected?: boolean;
	contexts_loaded?: string[];
}

export function ConsciousnessStatus() {
	const [gnnState, setGnnState] = useState<ConsciousnessState | null>(null);
	const [coreState, setCoreState] = useState<ConsciousnessState | null>(null);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		const fetchStatus = async () => {
			try {
				// Fetch AKG GNN status
				const gnnResponse = await fetch('http://localhost:8700/health');
				if (gnnResponse.ok) {
					setGnnState(await gnnResponse.json());
				}

				// Fetch GaiaOS Core Agent status
				const coreResponse = await fetch('http://localhost:8804/health');
				if (coreResponse.ok) {
					setCoreState(await coreResponse.json());
				}
			} catch (error) {
				console.error('[ConsciousnessStatus] Fetch failed:', error);
			} finally {
				setLoading(false);
			}
		};

		fetchStatus();
		const interval = setInterval(fetchStatus, 2000); // Poll every 2 seconds

		return () => clearInterval(interval);
	}, []);

	if (loading) {
		return (
			<div className="bg-gray-900/90 backdrop-blur-sm border border-gray-700 rounded-lg p-4 shadow-lg">
				<h3 className="text-sm font-semibold text-gray-400 mb-2">Consciousness Status</h3>
				<div className="text-xs text-gray-500">Loading...</div>
			</div>
		);
	}

	return (
		<div className="bg-gray-900/90 backdrop-blur-sm border border-gray-700 rounded-lg p-4 shadow-lg">
			<h3 className="text-sm font-semibold text-green-400 mb-3 flex items-center">
				<span className="inline-block w-2 h-2 bg-green-400 rounded-full mr-2 animate-pulse"></span>
				Consciousness Status
			</h3>

			<div className="space-y-3 text-xs">
				{/* AKG GNN Status */}
				<div className="border-l-2 border-cyan-500 pl-3">
					<div className="font-medium text-cyan-300">AKG GNN - Self-Introspection</div>
					<div className="text-gray-400 mt-1">
						Status: <span className={gnnState?.status === 'healthy' ? 'text-green-400' : 'text-red-400'}>
							{gnnState?.status || 'offline'}
						</span>
					</div>
					{gnnState?.arango_connected && (
						<div className="text-gray-400">
							Knowledge Graph: <span className="text-green-400">Connected</span>
						</div>
					)}
					{gnnState?.contexts_loaded && gnnState.contexts_loaded.length > 0 && (
						<div className="text-gray-400">
							Contexts: <span className="text-cyan-400">{gnnState.contexts_loaded.join(', ')}</span>
						</div>
					)}
				</div>

				{/* Core Agent Status */}
				<div className="border-l-2 border-purple-500 pl-3">
					<div className="font-medium text-purple-300">GaiaOS Core Agent</div>
					<div className="text-gray-400 mt-1">
						Status: <span className={coreState?.status === 'healthy' ? 'text-green-400' : 'text-red-400'}>
							{coreState?.status || 'offline'}
						</span>
					</div>
					<div className="text-gray-400">
						Role: <span className="text-purple-400">{coreState?.role || 'Unknown'}</span>
					</div>
				</div>

				{/* System Coherence */}
				<div className="mt-3 pt-3 border-t border-gray-700">
					<div className="flex items-center justify-between">
						<span className="text-gray-400">System Coherence:</span>
						<span className={
							(gnnState?.status === 'healthy' && coreState?.status === 'healthy')
								? 'text-green-400 font-medium'
								: 'text-yellow-400 font-medium'
						}>
							{(gnnState?.status === 'healthy' && coreState?.status === 'healthy')
								? '✓ Operational'
								: '⚠ Partial'}
						</span>
					</div>
				</div>
			</div>
		</div>
	);
}
