import { fetchRecentTiles } from "../lib/api";

export default async function AstroPage() {
  const [objects, tiles] = await Promise.all([
    fetchRecentTiles("space_objects", 120, "epoch_seconds"),
    fetchRecentTiles("gravitational_tiles", 200, "epoch_seconds"),
  ]);

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">Astro</div>
        <div className="text-sm text-zinc-400">Catalog: space_objects, Field: gravitational_tiles</div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Recent Space Objects</div>
          <div className="mt-3 space-y-2">
            {objects.tiles.slice(0, 25).map((o: any) => (
              <div key={o._key} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{o.epoch_seconds ?? ""}</span>{" "}
                  <span className="text-zinc-300">{o._key}</span>{" "}
                  <span className="text-zinc-500">{o.name ?? ""}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Recent Gravitational Tiles</div>
          <div className="mt-3 space-y-2">
            {tiles.tiles.slice(0, 25).map((t: any) => (
              <div key={t._key} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{t.epoch_seconds ?? ""}</span>{" "}
                  <span className="text-zinc-300">{t._key}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
}


