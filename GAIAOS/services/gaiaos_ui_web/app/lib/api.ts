import { ReflectionReport, RecentObservationsResponse, RecentTilesResponse, RecentValidationsResponse } from "./types";

function coreBase(): string {
  // Server-side: call core-agent directly (no browser secrets; read-only endpoints).
  return process.env.CORE_AGENT_URL ?? "http://core-agent:8804";
}

async function getJson<T>(url: string): Promise<T> {
  const resp = await fetch(url, { cache: "no-store" });
  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(`fetch failed ${resp.status}: ${text}`);
  }
  return (await resp.json()) as T;
}

export async function fetchReflection(): Promise<ReflectionReport> {
  return await getJson<ReflectionReport>(`${coreBase()}/api/reflection`);
}

export async function fetchRecentValidations(limit = 50): Promise<RecentValidationsResponse> {
  return await getJson<RecentValidationsResponse>(`${coreBase()}/api/validations/recent?limit=${encodeURIComponent(limit)}`);
}

export async function fetchRecentObservations(limit = 100, observerType?: string): Promise<RecentObservationsResponse> {
  const qs = new URLSearchParams();
  qs.set("limit", String(limit));
  if (observerType) qs.set("observer_type", observerType);
  return await getJson<RecentObservationsResponse>(`${coreBase()}/api/observations/recent?${qs.toString()}`);
}

export async function fetchRecentTiles(
  collection: string,
  limit = 200,
  sortField: string = "valid_time",
): Promise<RecentTilesResponse> {
  const qs = new URLSearchParams();
  qs.set("collection", collection);
  qs.set("limit", String(limit));
  qs.set("sort_field", sortField);
  return await getJson<RecentTilesResponse>(`${coreBase()}/api/tiles/recent?${qs.toString()}`);
}


