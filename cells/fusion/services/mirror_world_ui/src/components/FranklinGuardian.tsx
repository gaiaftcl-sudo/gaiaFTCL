import { useEffect, useState } from 'react';

interface GuardianState {
	service: string;
	status: string;
	role: string;
}

interface VirtueScore {
	truth: number;
	justice: number;
	mercy: number;
	wisdom: number;
	courage: number;
	temperance: number;
	prudence: number;
}

export function FranklinGuardian() {
	const [guardianState, setGuardianState] = useState<GuardianState | null>(null);
	const [loading, setLoading] = useState(true);

	// Simulated virtue scores - in production, these would come from Franklin Guardian API
	const [virtueScores] = useState<VirtueScore>({
		truth: 0.95,
		justice: 0.92,
		mercy: 0.88,
		wisdom: 0.91,
		courage: 0.87,
		temperance: 0.94,
		prudence: 0.93
	});

	useEffect(() => {
		const fetchStatus = async () => {
			try {
				const response = await fetch('http://localhost:8803/health');
				if (response.ok) {
					setGuardianState(await response.json());
				}
			} catch (error) {
				console.error('[FranklinGuardian] Fetch failed:', error);
			} finally {
				setLoading(false);
			}
		};

		fetchStatus();
		const interval = setInterval(fetchStatus, 2000);

		return () => clearInterval(interval);
	}, []);

	if (loading) {
		return (
			<div className="bg-gray-900/90 backdrop-blur-sm border border-gray-700 rounded-lg p-4 shadow-lg">
				<h3 className="text-sm font-semibold text-gray-400 mb-2">Franklin Guardian</h3>
				<div className="text-xs text-gray-500">Loading...</div>
			</div>
		);
	}

	return (
		<div className="bg-gray-900/90 backdrop-blur-sm border border-gray-700 rounded-lg p-4 shadow-lg">
			<h3 className="text-sm font-semibold text-blue-400 mb-3 flex items-center">
				<span className="inline-block w-2 h-2 bg-blue-400 rounded-full mr-2 animate-pulse"></span>
				Franklin Guardian
			</h3>

			<div className="space-y-3 text-xs">
				{/* Guardian Status */}
				<div className="border-l-2 border-blue-500 pl-3">
					<div className="font-medium text-blue-300">Constitutional Oversight</div>
					<div className="text-gray-400 mt-1">
						Status: <span className={guardianState?.status === 'healthy' ? 'text-green-400' : 'text-red-400'}>
							{guardianState?.status || 'offline'}
						</span>
					</div>
					<div className="text-gray-400">
						Role: <span className="text-blue-400">{guardianState?.role || 'Unknown'}</span>
					</div>
				</div>

				{/* Virtue Scores */}
				<div className="mt-3">
					<div className="font-medium text-gray-300 mb-2">Virtue Alignment</div>
					<div className="space-y-2">
						{Object.entries(virtueScores).map(([virtue, score]) => (
							<div key={virtue} className="flex items-center gap-2">
								<span className="text-gray-400 capitalize w-20">{virtue}:</span>
								<div className="flex-1 h-1.5 bg-gray-700 rounded-full overflow-hidden">
									<div
										className={`h-full transition-all duration-300 ${score >= 0.9 ? 'bg-green-500' :
												score >= 0.8 ? 'bg-yellow-500' :
													'bg-red-500'
											}`}
										style={{ width: `${score * 100}%` }}
									/>
								</div>
								<span className={`w-12 text-right font-mono ${score >= 0.9 ? 'text-green-400' :
										score >= 0.8 ? 'text-yellow-400' :
											'text-red-400'
									}`}>
									{(score * 100).toFixed(1)}%
								</span>
							</div>
						))}
					</div>
				</div>

				{/* Overall Alignment */}
				<div className="mt-3 pt-3 border-t border-gray-700">
					<div className="flex items-center justify-between">
						<span className="text-gray-400">Overall Alignment:</span>
						<span className="text-green-400 font-medium">
							{((Object.values(virtueScores).reduce((a, b) => a + b, 0) / Object.values(virtueScores).length) * 100).toFixed(1)}%
						</span>
					</div>
					<div className="text-gray-500 text-[10px] mt-1">
						Constitutional constraints: Active
					</div>
				</div>
			</div>
		</div>
	);
}
