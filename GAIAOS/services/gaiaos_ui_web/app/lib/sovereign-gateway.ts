/**
 * Server-only: call MCP gateway on the sovereign Docker network.
 * Prefer wallet-gate (GAIAFTCL_GATEWAY) so all paths honor cell constitution;
 * server-side calls use GAIAFTCL_INTERNAL_SERVICE_KEY when set.
 */
const DEFAULT_GATEWAY = "http://gaiaftcl-wallet-gate:8803";

/** Long-running AQL (materials COLLECT, full scans) — gateway HTTP client allows 60s; we allow 180s client-side. */
const FETCH_MS = 180_000;

function internalHeaders(): Record<string, string> {
  const k = process.env.GAIAFTCL_INTERNAL_SERVICE_KEY?.trim();
  if (k) return { "X-Gaiaftcl-Internal-Key": k };
  return {};
}

export function gatewayBase(): string {
  const u =
    process.env.GAIAFTCL_GATEWAY?.trim() ||
    process.env.GATEWAY_INTERNAL_URL?.trim() ||
    DEFAULT_GATEWAY;
  return u.replace(/\/$/, "");
}

export async function gatewayGet(path: string): Promise<{ ok: boolean; status: number; json: unknown }> {
  const url = `${gatewayBase()}${path.startsWith("/") ? path : `/${path}`}`;
  try {
    const r = await fetch(url, {
      headers: internalHeaders(),
      next: { revalidate: 0 },
      signal: AbortSignal.timeout(FETCH_MS),
    });
    const text = await r.text();
    let json: unknown = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = { raw: text.slice(0, 2000) };
    }
    return { ok: r.ok, status: r.status, json };
  } catch (e) {
    return { ok: false, status: 0, json: { error: String(e) } };
  }
}

export async function gatewayQuery(
  query: string,
  bind_vars: Record<string, unknown> = {}
): Promise<{ ok: boolean; status: number; rows: unknown[] }> {
  const url = `${gatewayBase()}/query`;
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...internalHeaders() },
      body: JSON.stringify({ query, bind_vars }),
      next: { revalidate: 0 },
      signal: AbortSignal.timeout(FETCH_MS),
    });
    let json: unknown;
    try {
      json = await r.json();
    } catch {
      json = null;
    }
    const rows = Array.isArray(json) ? json : [];
    return { ok: r.ok, status: r.status, rows };
  } catch (e) {
    return { ok: false, status: 0, rows: [{ error: String(e) }] };
  }
}
