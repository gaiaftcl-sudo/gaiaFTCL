import { fetchRecentValidations } from "../lib/api";

export default async function ClosureProofPage() {
  let validations: { validations?: Array<{ _key?: string; timestamp?: string; target_collection?: string; passed?: boolean; keys?: string[]; failures?: string[] }> } = { validations: [] };
  try {
    validations = await fetchRecentValidations(50);
  } catch {
    // core-agent may be unavailable in local dev
  }
  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">Closure Proof</div>
        <div className="text-sm text-zinc-400">Latest QFOT validation artifacts (field_validations)</div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="text-sm font-semibold text-white">Recent Validations</div>
        <div className="mt-3 space-y-2">
          {(validations.validations ?? []).map((v: any) => (
            <div key={v._key ?? `${v.timestamp}-${v.target_collection}`} className="rounded-md bg-zinc-900 px-3 py-2">
              <div className="flex items-center justify-between">
                <div className="text-xs text-zinc-200">
                  <span className="font-mono text-zinc-400">{v.timestamp}</span>{" "}
                  <span className="text-zinc-300">{v.target_collection}</span>{" "}
                  <span className="text-zinc-500">{(v.keys ?? []).length} keys</span>
                </div>
                <div className={["text-xs font-semibold", v.passed ? "text-emerald-400" : "text-amber-400"].join(" ")}>
                  {v.passed ? "PASS" : "FAIL"}
                </div>
              </div>
              {(v.failures ?? []).length > 0 && (
                <div className="mt-2 text-xs text-zinc-400">
                  {v.failures.slice(0, 3).join(" | ")}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}


