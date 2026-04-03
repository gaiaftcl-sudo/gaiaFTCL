// GaiaOS Mirror World UI - High-Performance Canvas Map Renderer
import React, { useRef, useEffect, useCallback } from 'react';
import { Dimension, WorldState } from '../types/schema';
import { getFlightStyle, getWeatherStyle } from '../hooks/useContextRenderer';

interface Props {
	data: WorldState | null;
	dimension: Dimension;
	onSelect: (id: string | null) => void;
	selectedId: string | null;
}

export const MirrorMap: React.FC<Props> = ({ data, dimension, onSelect, selectedId }) => {
	const canvasRef = useRef<HTMLCanvasElement>(null);
	const containerRef = useRef<HTMLDivElement>(null);
	const flightPositionsRef = useRef<Map<string, { x: number; y: number }>>(new Map());

	// Map Projection (Equirectangular for global view)
	const project = useCallback((lat: number, lon: number, w: number, h: number) => ({
		x: (lon + 180) * (w / 360),
		y: (90 - lat) * (h / 180)
	}), []);

	// Draw heading indicator
	const drawHeadingLine = useCallback((
		ctx: CanvasRenderingContext2D,
		x: number,
		y: number,
		heading: number,
		speed: number,
		color: string
	) => {
		const length = Math.min(30, 10 + speed / 50);
		const rad = (heading - 90) * Math.PI / 180;
		const endX = x + Math.cos(rad) * length;
		const endY = y + Math.sin(rad) * length;

		ctx.strokeStyle = color;
		ctx.lineWidth = 1;
		ctx.globalAlpha = 0.6;
		ctx.beginPath();
		ctx.moveTo(x, y);
		ctx.lineTo(endX, endY);
		ctx.stroke();
	}, []);

	const draw = useCallback(() => {
		const canvas = canvasRef.current;
		if (!canvas || !data) return;
		const ctx = canvas.getContext('2d');
		if (!ctx) return;

		// Setup Canvas (High DPI)
		const rect = canvas.getBoundingClientRect();
		const dpr = window.devicePixelRatio || 1;
		canvas.width = rect.width * dpr;
		canvas.height = rect.height * dpr;
		ctx.scale(dpr, dpr);
		ctx.clearRect(0, 0, rect.width, rect.height);

		// Clear position cache
		flightPositionsRef.current.clear();

		// 1. Draw Weather Layer (Bottom)
		data.weather.forEach(cell => {
			const style = getWeatherStyle(cell, dimension);
			if (!style.visible || cell.poly.length < 3) return;

			ctx.fillStyle = style.color;
			ctx.strokeStyle = style.color;
			ctx.lineWidth = style.strokeWidth;
			ctx.globalAlpha = style.opacity;

			ctx.beginPath();
			cell.poly.forEach((pt, i) => {
				const { x, y } = project(pt[1], pt[0], rect.width, rect.height);
				if (i === 0) ctx.moveTo(x, y);
				else ctx.lineTo(x, y);
			});
			ctx.closePath();
			ctx.fill();

			// Draw outline for severe weather
			if (cell.severity > 0.5) {
				ctx.globalAlpha = style.opacity + 0.2;
				ctx.stroke();
			}
		});

		// 2. Draw Aircraft Layer (Top)
		data.flights.forEach(flight => {
			const style = getFlightStyle(flight, dimension);
			const { x, y } = project(flight.position.lat, flight.position.lon, rect.width, rect.height);

			// Cache position for hit testing
			flightPositionsRef.current.set(flight.id, { x, y });

			// Draw Trail
			if (style.showTrail && flight.trajectory.length > 1) {
				ctx.strokeStyle = style.color;
				ctx.lineWidth = 1;
				ctx.globalAlpha = 0.3;
				ctx.setLineDash([3, 3]);
				ctx.beginPath();
				flight.trajectory.forEach((pt, i) => {
					const t = project(pt.lat, pt.lon, rect.width, rect.height);
					if (i === 0) ctx.moveTo(t.x, t.y);
					else ctx.lineTo(t.x, t.y);
				});
				ctx.stroke();
				ctx.setLineDash([]);
			}

			// Draw Heading Line
			drawHeadingLine(ctx, x, y, flight.vector.heading, flight.vector.speed_kts, style.color);

			// Draw Icon
			ctx.fillStyle = style.color;
			ctx.globalAlpha = style.fillOpacity;
			const s = 4 * style.scale;

			ctx.beginPath();
			if (style.icon === 'triangle') {
				// Warning triangle
				ctx.moveTo(x, y - s * 1.2);
				ctx.lineTo(x + s, y + s * 0.8);
				ctx.lineTo(x - s, y + s * 0.8);
			} else if (style.icon === 'diamond') {
				// Diamond shape
				ctx.moveTo(x, y - s);
				ctx.lineTo(x + s, y);
				ctx.lineTo(x, y + s);
				ctx.lineTo(x - s, y);
			} else {
				// Standard target (circle)
				ctx.arc(x, y, s, 0, Math.PI * 2);
			}
			ctx.closePath();
			ctx.fill();

			// Selection ring
			if (flight.id === selectedId) {
				ctx.strokeStyle = '#ffffff';
				ctx.lineWidth = 2;
				ctx.globalAlpha = 1;
				ctx.beginPath();
				ctx.arc(x, y, s * 2, 0, Math.PI * 2);
				ctx.stroke();
			}

			// Alert ring (pulsing)
			if (style.alert) {
				const pulseSize = s * 2 + Math.sin(Date.now() / 200) * 3;
				ctx.strokeStyle = '#ef4444';
				ctx.lineWidth = 1;
				ctx.globalAlpha = 0.5;
				ctx.beginPath();
				ctx.arc(x, y, pulseSize, 0, Math.PI * 2);
				ctx.stroke();
			}

			// Draw Label (Data Block)
			if (style.showLabel) {
				ctx.fillStyle = '#ffffff';
				ctx.font = 'bold 10px "Fira Code", monospace';
				ctx.globalAlpha = 1.0;

				// Offset label to avoid overlap
				const labelX = x + 10;
				const labelY = y - 4;

				// Background for readability
				const callsignWidth = ctx.measureText(flight.callsign).width;
				ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
				ctx.fillRect(labelX - 2, labelY - 10, callsignWidth + 4, 24);

				// Callsign
				ctx.fillStyle = '#ffffff';
				ctx.fillText(flight.callsign, labelX, labelY);

				// Secondary info (altitude/speed)
				ctx.fillStyle = '#9ca3af';
				ctx.font = '9px "Fira Code", monospace';
				const alt = Math.floor(flight.position.alt_ft / 100).toString().padStart(3, '0');
				const spd = Math.floor(flight.vector.speed_kts / 10).toString().padStart(2, '0');
				ctx.fillText(`${alt} ${spd}`, labelX, labelY + 10);
			}
		});

		// 3. Draw coordinate grid overlay
		ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
		ctx.lineWidth = 1;
		ctx.globalAlpha = 1;

		// Latitude lines
		for (let lat = -60; lat <= 60; lat += 30) {
			const { y } = project(lat, 0, rect.width, rect.height);
			ctx.beginPath();
			ctx.moveTo(0, y);
			ctx.lineTo(rect.width, y);
			ctx.stroke();
		}

		// Longitude lines
		for (let lon = -180; lon <= 180; lon += 30) {
			const { x } = project(0, lon, rect.width, rect.height);
			ctx.beginPath();
			ctx.moveTo(x, 0);
			ctx.lineTo(x, rect.height);
			ctx.stroke();
		}
	}, [data, dimension, selectedId, project, drawHeadingLine]);

	// Animation loop
	useEffect(() => {
		let animationId: number;
		const loop = () => {
			draw();
			animationId = requestAnimationFrame(loop);
		};
		loop();
		return () => cancelAnimationFrame(animationId);
	}, [draw]);

	// Hit testing for click selection
	const handleClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
		const canvas = canvasRef.current;
		if (!canvas || !data) return;

		const rect = canvas.getBoundingClientRect();
		const x = e.clientX - rect.left;
		const y = e.clientY - rect.top;

		// Find closest flight within 20px
		let closestId: string | null = null;
		let closestDist = 20;

		flightPositionsRef.current.forEach((pos, id) => {
			const dist = Math.sqrt((pos.x - x) ** 2 + (pos.y - y) ** 2);
			if (dist < closestDist) {
				closestDist = dist;
				closestId = id;
			}
		});

		onSelect(closestId);
	}, [data, onSelect]);

	return (
		<div ref={containerRef} className="absolute inset-0 z-0">
			{/* Background Pattern */}
			<div
				className="absolute inset-0 opacity-30 pointer-events-none"
				style={{
					backgroundImage: 'radial-gradient(circle at 50% 50%, #1f2937 1px, transparent 1px)',
					backgroundSize: '40px 40px'
				}}
			/>

			<canvas
				ref={canvasRef}
				className="w-full h-full block cursor-crosshair"
				onClick={handleClick}
			/>
		</div>
	);
};

export default MirrorMap;

