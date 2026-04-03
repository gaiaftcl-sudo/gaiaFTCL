import { fetchRecentTiles } from "../lib/api";

export default async function MolecularPage() {
  const [tiles, drugs] = await Promise.all([
    fetchRecentTiles("molecular_tiles", 200, "ingest_timestamp"),
    fetchRecentTiles("drug_molecules", 50, "ingest_timestamp"),
  ]);

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">Molecular</div>
        <div className="text-sm text-zinc-400">Tiles: molecular_tiles, Registry: drug_molecules</div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Recent Molecular Tiles</div>
          <div className="mt-3 space-y-2">
            {tiles.tiles.slice(0, 25).map((t: any) => (
              <div key={t._key} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{t.ingest_timestamp ?? ""}</span>{" "}
                  <span className="text-zinc-300">{t._key}</span>{" "}
                  <span className="text-zinc-500">{t.protein_id ?? ""}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Drug Molecules</div>
          <div className="mt-3 space-y-2">
            {drugs.tiles.slice(0, 25).map((d: any) => (
              <div key={d._key} className="rounded-md bg-zinc-900 px-3 py-2">
                <div className="text-xs text-zinc-200">
                  <span className="text-zinc-300">{d._key}</span>{" "}
                  <span className="text-zinc-500">{d.name ?? ""}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
}


