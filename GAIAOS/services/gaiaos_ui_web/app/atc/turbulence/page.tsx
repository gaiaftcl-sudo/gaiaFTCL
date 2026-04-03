"use client";

import "maplibre-gl/dist/maplibre-gl.css";

import { useEffect, useState } from "react";
import Map, { Layer, Source } from "react-map-gl/maplibre";

type TurbulenceAlert = {
  location: { lat: number; lon: number };
  altitude_m: number;
  flight_level: number;
  severity: string;
  probability: number;
  valid_time: number;
  expires_time: number;
  richardson_number: number;
  eddy_dissipation_rate: number;
  wind_shear: number;
  affected_routes: string[];
};

type TurbulenceNOTAM = {
  notam_id: string;
  issued: number;
  valid_from: number;
  valid_until: number;
  location: string;
  flight_levels: string;
  severity: string;
  message: string;
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

export default function ATCTurbulencePage() {
  const [alerts, setAlerts] = useState<TurbulenceAlert[]>([]);
  const [notams, setNotams] = useState<TurbulenceNOTAM[]>([]);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let stopped = false;

    async function tick() {
      try {
        setErr(null);
        const [aResp, nResp] = await Promise.all([
          fetch("/api/turbulence/alerts?min_probability=0.5&forecast_hours=6", { cache: "no-store" }),
          fetch("/api/turbulence/notams", { cache: "no-store" }),
        ]);

        if (!aResp.ok) throw new Error(await aResp.text());
        if (!nResp.ok) throw new Error(await nResp.text());

        const [a, n] = await Promise.all([aResp.json(), nResp.json()]);
        if (stopped) return;
        setAlerts(Array.isArray(a) ? a : []);
        setNotams(Array.isArray(n) ? n : []);
      } catch (e: any) {
        if (stopped) return;
        setErr(String(e?.message ?? e ?? "unknown error"));
      }
    }

    tick();
    const id = setInterval(tick, 30000); // Update every 30s
    return () => {
      stopped = true;
      clearInterval(id);
    };
  }, []);

  const alertGeoJSON = {
    type: "FeatureCollection" as const,
    features: alerts.map((a) => ({
      type: "Feature" as const,
      geometry: { type: "Point" as const, coordinates: [a.location.lon, a.location.lat] },
      properties: {
        severity: a.severity,
        probability: a.probability,
        edr: a.eddy_dissipation_rate,
        fl: a.flight_level,
      },
    })),
  };

  const highAlerts = alerts.filter((a) => a.probability >= 0.7);
  const moderateAlerts = alerts.filter((a) => a.probability >= 0.5 && a.probability < 0.7);

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">ATC Turbulence Alerts (LIVE)</div>
        <div className="text-sm text-zinc-400">
          Clear Air Turbulence forecast from NOAA GFS flight-level data. Richardson number + EDR + wind shear → 1-6 hour lead time.
        </div>
      </div>

      {err ? (
        <div className="mb-4 rounded-xl border border-red-900 bg-red-950/40 p-3 text-sm text-red-200">
          {err}
        </div>
      ) : null}

      <div className="grid gap-3 md:grid-cols-4">
        <MetricCard label="Total alerts" value={String(alerts.length)} tone={alerts.length > 0 ? "warn" : "ok"} />
        <MetricCard label="High probability (≥70%)" value={String(highAlerts.length)} tone={highAlerts.length > 0 ? "bad" : "ok"} />
        <MetricCard label="Moderate (50-70%)" value={String(moderateAlerts.length)} tone={moderateAlerts.length > 0 ? "warn" : "ok"} />
        <MetricCard label="NOTAMs issued" value={String(notams.length)} tone={notams.length > 0 ? "warn" : "ok"} />
      </div>

      <div className="mt-4 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
        <div className="border-b border-zinc-800 px-4 py-2 text-xs text-zinc-400">
          Map: turbulence alerts (heat) color-coded by probability. Click for details.
        </div>
        <div className="h-[560px] w-full">
          <Map
            initialViewState={{ longitude: -95, latitude: 40, zoom: 3.5 }}
            style={{ width: "100%", height: "100%" }}
            mapStyle="https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json"
          >
            <Source id="alerts" type="geojson" data={alertGeoJSON}>
              <Layer
                id="alert-heat"
                type="heatmap"
                paint={{
                  "heatmap-weight": ["interpolate", ["linear"], ["get", "probability"], 0, 0, 1, 1],
                  "heatmap-intensity": 1.2,
                  "heatmap-radius": 35,
                  "heatmap-opacity": 0.9,
                  "heatmap-color": [
                    "interpolate",
                    ["linear"],
                    ["heatmap-density"],
                    0,
                    "rgba(0,0,0,0)",
                    0.2,
                    "rgba(59,130,246,0.3)",
                    0.5,
                    "rgba(245,158,11,0.6)",
                    0.8,
                    "rgba(239,68,68,0.9)",
                  ],
                }}
              />
            </Source>
          </Map>
        </div>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Active NOTAMs ({notams.length})</div>
          <div className="mt-3 space-y-2 max-h-96 overflow-y-auto">
            {notams.map((n) => (
              <div key={n.notam_id} className="rounded-md border border-red-900 bg-red-950/20 px-3 py-2">
                <div className="text-xs font-mono text-red-400">{n.notam_id}</div>
                <div className="mt-1 text-xs text-zinc-300 whitespace-pre-wrap">{n.message}</div>
              </div>
            ))}
            {notams.length === 0 ? <div className="text-xs text-zinc-500">No NOTAMs currently active.</div> : null}
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Alert details (sample)</div>
          <div className="mt-3 space-y-2 max-h-96 overflow-y-auto">
            {alerts.slice(0, 20).map((a, idx) => (
              <div key={idx} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-amber-400">FL{a.flight_level}</span>{" "}
                  <span className="text-zinc-300">{a.severity}</span>{" "}
                  <span className="text-zinc-500">
                    ({a.location.lat.toFixed(2)}°, {a.location.lon.toFixed(2)}°)
                  </span>
                </div>
                <div className="mt-1 text-xs text-zinc-400">
                  Prob: {(a.probability * 100).toFixed(0)}% | EDR: {a.eddy_dissipation_rate.toFixed(2)} | Ri: {a.richardson_number.toFixed(2)}
                </div>
                {a.affected_routes.length > 0 && (
                  <div className="mt-1 text-xs text-yellow-400">
                    Affected: {a.affected_routes.slice(0, 3).join(", ")}
                    {a.affected_routes.length > 3 ? ` +${a.affected_routes.length - 3} more` : ""}
                  </div>
                )}
              </div>
            ))}
            {alerts.length === 0 ? <div className="text-xs text-zinc-500">No alerts returned.</div> : null}
          </div>
        </div>
      </div>
    </main>
  );
}

