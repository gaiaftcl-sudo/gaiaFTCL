import { fetchRecentObservations, fetchRecentTiles } from "../lib/api";

export default async function OceanPage() {
  const [tiles, obsBuoy, obsCmems] = await Promise.all([
    fetchRecentTiles("ocean_tiles", 200, "valid_time"),
    fetchRecentObservations(100, "ocean_buoy"),
    fetchRecentObservations(100, "ocean_cmems"),
  ]);

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">Ocean</div>
        <div className="text-sm text-zinc-400">Tiles: ocean_tiles, Observations: ocean_buoy + ocean_cmems</div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Recent Tiles</div>
          <div className="mt-3 space-y-2">
            {tiles.tiles.slice(0, 25).map((t: any) => (
              <div key={t._key} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{t.valid_time}</span>{" "}
                  <span className="text-zinc-300">{t._key}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Recent Observations</div>
          <div className="mt-3 space-y-2">
            {[...obsCmems.observations.slice(0, 12), ...obsBuoy.observations.slice(0, 13)].map((o: any) => (
              <div key={o._key} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{o.timestamp}</span>{" "}
                  <span className="text-zinc-300">{o.observer_type}</span>{" "}
                  <span className="text-zinc-500">{o._key}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
}


