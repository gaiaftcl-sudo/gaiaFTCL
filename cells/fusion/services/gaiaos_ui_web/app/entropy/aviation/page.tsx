"use client";

import "maplibre-gl/dist/maplibre-gl.css";

import { useEffect, useMemo, useState } from "react";
import Map, { Layer, Source } from "react-map-gl/maplibre";

type DensityAnomaly = {
  lat: number;
  lon: number;
  altitude_m: number;
  pressure_level_mb: number;
  anomaly_pct: number;
  timestamp: number;
  source: string;
};

type LiveFlight = {
  icao24: string;
  callsign: string;
  aircraft_type?: string | null;
  lat: number;
  lon: number;
  altitude_ft: number;
  velocity_kts: number;
  timestamp: number;
};

type WasteMetrics = {
  total_waste_kg: number;
  affected_flights: number;
  waste_rate_kg_per_hour: number;
  cost_rate_usd_per_hour: number;
  window_seconds: number;
};

function MetricCard({ label, value, tone }: { label: string; value: string; tone?: "ok" | "warn" | "bad" }) {
  const color =
    tone === "bad" ? "text-red-400" : tone === "warn" ? "text-amber-300" : "text-emerald-300";
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{label}</div>
      <div className={`mt-1 text-2xl font-semibold ${color}`}>{value}</div>
    </div>
  );
}

export default function AviationEntropyPage() {
  const [anomalies, setAnomalies] = useState<DensityAnomaly[]>([]);
  const [flights, setFlights] = useState<LiveFlight[]>([]);
  const [waste, setWaste] = useState<WasteMetrics | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let stopped = false;

    async function tick() {
      try {
        setErr(null);
        const [aResp, fResp, wResp] = await Promise.all([
          fetch("/api/entropy/aviation/anomalies?min_anomaly_pct=2&max_age_seconds=86400", { cache: "no-store" }),
          fetch("/api/entropy/aviation/flights?max_age_seconds=300", { cache: "no-store" }),
          fetch("/api/entropy/aviation/waste?min_anomaly_pct=2&max_age_seconds=86400", { cache: "no-store" }),
        ]);

        if (!aResp.ok) throw new Error(await aResp.text());
        if (!fResp.ok) throw new Error(await fResp.text());
        if (!wResp.ok) throw new Error(await wResp.text());

        const [a, f, w] = await Promise.all([aResp.json(), fResp.json(), wResp.json()]);
        if (stopped) return;
        setAnomalies(Array.isArray(a) ? a : []);
        setFlights(Array.isArray(f) ? f : []);
        setWaste(w ?? null);
      } catch (e: any) {
        if (stopped) return;
        setErr(String(e?.message ?? e ?? "unknown error"));
      }
    }

    tick();
    const id = setInterval(tick, 5000);
    return () => {
      stopped = true;
      clearInterval(id);
    };
  }, []);

  const anomalyGeoJSON = useMemo(() => {
    return {
      type: "FeatureCollection" as const,
      features: anomalies.map((a) => ({
        type: "Feature" as const,
        geometry: { type: "Point" as const, coordinates: [a.lon, a.lat] },
        properties: { anomaly_pct: a.anomaly_pct, altitude_m: a.altitude_m, pressure_level_mb: a.pressure_level_mb },
      })),
    };
  }, [anomalies]);

  const flightGeoJSON = useMemo(() => {
    return {
      type: "FeatureCollection" as const,
      features: flights.map((f) => ({
        type: "Feature" as const,
        geometry: { type: "Point" as const, coordinates: [f.lon, f.lat] },
        properties: { callsign: f.callsign, altitude_ft: f.altitude_ft, velocity_kts: f.velocity_kts },
      })),
    };
  }, [flights]);

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">Entropy · Aviation (LIVE)</div>
        <div className="text-sm text-zinc-400">
          Density anomalies (flight levels) → drag penalty → fuel waste. Data source: NOAA GFS flight-level ingest + airplanes.live ATC.
        </div>
      </div>

      {err ? (
        <div className="mb-4 rounded-xl border border-red-900 bg-red-950/40 p-3 text-sm text-red-200">
          {err}
        </div>
      ) : null}

      <div className="grid gap-3 md:grid-cols-4">
        <MetricCard label="Anomaly tiles (≥2%)" value={String(anomalies.length)} tone={anomalies.length > 0 ? "warn" : "ok"} />
        <MetricCard label="Live flights (5m)" value={String(flights.length)} tone="ok" />
        <MetricCard
          label="Waste rate (kg/hr)"
          value={waste ? waste.waste_rate_kg_per_hour.toFixed(2) : "…"}
          tone={waste && waste.waste_rate_kg_per_hour > 0 ? "bad" : "ok"}
        />
        <MetricCard
          label="Cost rate ($/hr)"
          value={waste ? `$${waste.cost_rate_usd_per_hour.toFixed(2)}` : "…"}
          tone={waste && waste.cost_rate_usd_per_hour > 0 ? "bad" : "ok"}
        />
      </div>

      <div className="mt-4 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
        <div className="border-b border-zinc-800 px-4 py-2 text-xs text-zinc-400">
          Map: anomalies (heat) + flights (green). Lon is 0–360 in GaiaOS tiles; flights are normalized in proxy to 0–360.
        </div>
        <div className="h-[560px] w-full">
          <Map
            initialViewState={{ longitude: -40, latitude: 45, zoom: 2.2 }}
            style={{ width: "100%", height: "100%" }}
            mapStyle="https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json"
          >
            <Source id="anomalies" type="geojson" data={anomalyGeoJSON}>
              <Layer
                id="anomaly-heat"
                type="heatmap"
                paint={{
                  "heatmap-weight": ["interpolate", ["linear"], ["get", "anomaly_pct"], 0, 0, 10, 1],
                  "heatmap-intensity": 1,
                  "heatmap-radius": 28,
                  "heatmap-opacity": 0.85,
                  "heatmap-color": [
                    "interpolate",
                    ["linear"],
                    ["heatmap-density"],
                    0,
                    "rgba(0,0,0,0)",
                    0.25,
                    "rgba(16,185,129,0.25)",
                    0.6,
                    "rgba(245,158,11,0.5)",
                    1,
                    "rgba(239,68,68,0.9)",
                  ],
                }}
              />
            </Source>

            <Source id="flights" type="geojson" data={flightGeoJSON}>
              <Layer
                id="flight-dots"
                type="circle"
                paint={{
                  "circle-radius": 3,
                  "circle-color": "rgba(16,185,129,0.9)",
                  "circle-stroke-width": 0.5,
                  "circle-stroke-color": "rgba(0,0,0,0.8)",
                }}
              />
            </Source>
          </Map>
        </div>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Top anomalies (sample)</div>
          <div className="mt-3 space-y-2">
            {anomalies.slice(0, 15).map((a, idx) => (
              <div key={`${a.timestamp}_${idx}`} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{a.timestamp}</span>{" "}
                  <span className="text-zinc-300">{a.anomaly_pct.toFixed(2)}%</span>{" "}
                  <span className="text-zinc-500">
                    ({a.lat.toFixed(2)}, {a.lon.toFixed(2)}) L{a.pressure_level_mb}mb
                  </span>
                </div>
              </div>
            ))}
            {anomalies.length === 0 ? <div className="text-xs text-zinc-500">No anomalies returned.</div> : null}
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Live flights (sample)</div>
          <div className="mt-3 space-y-2">
            {flights.slice(0, 15).map((f) => (
              <div key={`${f.icao24}_${f.timestamp}`} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{f.timestamp}</span>{" "}
                  <span className="text-zinc-300">{f.callsign}</span>{" "}
                  <span className="text-zinc-500">
                    ({f.lat.toFixed(2)}, {f.lon.toFixed(2)}) {Math.round(f.altitude_ft)}ft {Math.round(f.velocity_kts)}kt
                  </span>
                </div>
              </div>
            ))}
            {flights.length === 0 ? <div className="text-xs text-zinc-500">No flights returned.</div> : null}
          </div>
        </div>
      </div>
    </main>
  );
}


