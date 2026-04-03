import { fetchReflection, fetchRecentValidations } from "./lib/api";
import DownloadButton from "./components/DownloadButton";

function card(label: string, value: string | number) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs font-medium text-zinc-400">{label}</div>
      <div className="mt-1 text-2xl font-semibold text-white">{value}</div>
    </div>
  );
}

export default async function Home() {
  let reflection: { collection_counts?: Array<{ collection: string; count: number }>; recommended_next_worlds?: Array<{ world: string; rationale: string }> } = { collection_counts: [], recommended_next_worlds: [] };
  let validations: { validations?: Array<{ _key?: string; timestamp?: string; target_collection?: string; passed?: boolean }> } = { validations: [] };
  try {
    [reflection, validations] = await Promise.all([fetchReflection(), fetchRecentValidations(10)]);
  } catch {
    // core-agent may be unavailable in local dev
  }
  const counts = new Map((reflection.collection_counts ?? []).map((c) => [c.collection, c.count]));

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <DownloadButton />
      
      <div className="mb-4 mt-6">
        <div className="text-xl font-semibold text-white">Dashboard</div>
        <div className="text-sm text-zinc-400">Live substrate state from GaiaFTCL core-agent (evidence-only).</div>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {card("Observations", counts.get("observations") ?? "—")}
        {card("Atmosphere Tiles", counts.get("atmosphere_tiles") ?? "—")}
        {card("Ocean Tiles", counts.get("ocean_tiles") ?? "—")}
        {card("Biosphere Tiles", counts.get("biosphere_tiles") ?? "—")}
        {card("Molecular Tiles", counts.get("molecular_tiles") ?? "—")}
        {card("Gravitational Tiles", counts.get("gravitational_tiles") ?? "—")}
        {card("Field Validations", counts.get("field_validations") ?? "—")}
        {card("FoT Claims", counts.get("mcp_claims") ?? "—")}
      </div>

      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Latest Validations</div>
          <div className="mt-3 space-y-2">
            {(validations.validations ?? []).slice(0, 10).map((v: any) => (
              <div
                key={v._key ?? `${v.timestamp}-${v.target_collection}`}
                className="flex items-center justify-between rounded-md bg-zinc-900 px-3 py-2"
              >
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{v.timestamp}</span>{" "}
                  <span className="text-zinc-300">{v.target_collection}</span>
                </div>
                <div className={["text-xs font-semibold", v.passed ? "text-emerald-400" : "text-amber-400"].join(" ")}>
                  {v.passed ? "PASS" : "FAIL"}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">GaiaFTCL Next Worlds</div>
          <div className="mt-3 space-y-3">
            {(reflection.recommended_next_worlds ?? []).slice(0, 2).map((r) => (
              <div key={r.world} className="rounded-md bg-zinc-900 p-3">
                <div className="text-sm font-semibold text-zinc-100">{r.world}</div>
                <div className="mt-1 text-xs text-zinc-400">{r.rationale}</div>
              </div>
            ))}
            {(reflection.recommended_next_worlds ?? []).length === 0 && (
              <div className="text-xs text-zinc-400">No recommendation returned.</div>
            )}
          </div>
        </div>
      </div>
    </main>
  );
}
