import { NextResponse } from "next/server";
import fs from "fs";
import path from "path";
import { gatewayGet, gatewayQuery } from "@/app/lib/sovereign-gateway";
import { normalizeDiscoveryRow } from "@/app/lib/sovereign-substrate";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/** Baseline game rooms (mail adapter + mesh). Merged with substrate COLLECT. */
const GAME_ROOMS_BASE = [
  "owl_protocol",
  "discovery",
  "governance",
  "treasury",
  "sovereign_mesh",
  "receipt_wall",
  "open_loop_tracker",
  "unclassified",
];

const DEFAULT_MESH_CELLS = [
  { name: "gaiaftcl-hcloud-hel1-01", ipv4: "77.42.85.60", role: "head / gateway" },
  { name: "gaiaftcl-hcloud-hel1-02", ipv4: "135.181.88.134", role: "Franklin" },
  { name: "gaiaftcl-hcloud-hel1-03", ipv4: "77.42.32.156", role: "Fara" },
  { name: "gaiaftcl-hcloud-hel1-04", ipv4: "77.42.88.110", role: "mesh" },
  { name: "gaiaftcl-hcloud-hel1-05", ipv4: "37.27.7.9", role: "mesh" },
  { name: "gaiaftcl-hcloud-nbg1-01", ipv4: "37.120.187.247", role: "Netcup" },
  { name: "gaiaftcl-hcloud-nbg1-02", ipv4: "152.53.91.220", role: "Netcup" },
  { name: "gaiaftcl-hcloud-nbg1-03", ipv4: "152.53.88.141", role: "Netcup" },
  { name: "gaiaftcl-hcloud-nbg1-04", ipv4: "37.120.187.174", role: "Netcup" },
];

const RECEIPT_MARKERS = ["20260327T124650Z"];

function statusStr(c: Record<string, unknown>): string {
  return String(c.status ?? c.type ?? "").toLowerCase();
}

function isClosedStatus(s: string): boolean {
  if (s === "closed") return true;
  return (
    s.includes("settled") ||
    s.includes("witnessed") ||
    s.includes("sealed") ||
    s.includes("complete") ||
    s.includes("resolved")
  );
}

function isOpenStatus(s: string): boolean {
  if (isClosedStatus(s)) return false;
  return (
    s.includes("open") ||
    s.includes("draft") ||
    s.includes("pending") ||
    s.includes("submitted") ||
    s.includes("unresolved") ||
    s === "" ||
    s.includes("active")
  );
}

function claimTime(c: Record<string, unknown>): number {
  const t = c.created_at ?? c.timestamp ?? c._key;
  if (typeof t === "string") {
    const d = Date.parse(t);
    if (!Number.isNaN(d)) return d;
  }
  return 0;
}

function ageDays(c: Record<string, unknown>): number {
  const ms = claimTime(c);
  if (!ms) return 0;
  return Math.floor((Date.now() - ms) / (86400 * 1000));
}

function claimDedupeKey(c: Record<string, unknown>): string {
  return String(c._key ?? c.id ?? "");
}

function claimHasReceiptMarker(c: Record<string, unknown>): boolean {
  const blob = JSON.stringify(c);
  return RECEIPT_MARKERS.some((m) => blob.includes(m));
}

async function listDiscoveredCollectionNames(): Promise<string[]> {
  const q = `FOR c IN COLLECTIONS()
    FILTER c.type == 2
    FILTER LIKE(c.name, "discovered_%", true)
    SORT c.name
    RETURN c.name`;
  const r = await gatewayQuery(q);
  if (!r.ok || !r.rows.length) {
    return [
      "discovered_molecules",
      "discovered_compounds",
      "discovered_proteins",
      "discovered_materials",
      "discovered_mofs",
      "discovered_superconductors",
      "discovered_fluid_dynamics",
      "discovered_trading_strategies",
      "discovered_clinical_trials",
      "discovered_nfl_plays",
    ];
  }
  return (r.rows as string[]).filter(Boolean);
}

async function meshHeartbeatRegistry(): Promise<Record<string, unknown>> {
  const base = (process.env.MESH_PEER_REGISTRY_URL || "http://gaiaftcl-mesh-peer-registry:8821").replace(
    /\/$/,
    "",
  );
  try {
    const r = await fetch(`${base}/peers`, {
      signal: AbortSignal.timeout(10_000),
      next: { revalidate: 0 },
    });
    if (!r.ok) {
      return { source: "registry_http_error", status: r.status };
    }
    const body = (await r.json()) as Record<string, unknown>;
    return { source: "nats_mesh.cell.heartbeat", ...body };
  } catch (e) {
    return { source: "registry_unreachable", error: String(e) };
  }
}

async function hetznerMeshStatus() {
  const token = process.env.HCLOUD_TOKEN;
  if (!token) {
    return {
      source: "static_defaults" as const,
      cells: DEFAULT_MESH_CELLS.map((c) => ({
        ...c,
        hetzner_status: null as string | null,
        hetzner_id: null as number | null,
      })),
      note: "Set HCLOUD_TOKEN on gaiaftcl-sovereign-ui for live Hetzner API status.",
    };
  }
  try {
    const r = await fetch("https://api.hetzner.cloud/v1/servers", {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(25_000),
    });
    if (!r.ok) {
      return {
        source: "hetzner_error" as const,
        status: r.status,
        cells: DEFAULT_MESH_CELLS.map((c) => ({ ...c, hetzner_status: null, hetzner_id: null })),
      };
    }
    const body = (await r.json()) as {
      servers?: Array<{ id: number; name: string; status: string; public_net?: { ipv4?: { ip?: string } } }>;
    };
    const servers = body.servers || [];
    const byName = new Map(servers.map((s) => [s.name, s]));
    const byIp = new Map(servers.map((s) => [s.public_net?.ipv4?.ip ?? "", s]));
    return {
      source: "hetzner_api" as const,
      cells: DEFAULT_MESH_CELLS.map((c) => {
        const s = byName.get(c.name) ?? byIp.get(c.ipv4);
        return {
          ...c,
          hetzner_status: s?.status ?? "not_listed",
          hetzner_id: s?.id ?? null,
        };
      }),
    };
  } catch (e) {
    return {
      source: "hetzner_fetch_failed" as const,
      error: String(e),
      cells: DEFAULT_MESH_CELLS.map((c) => ({ ...c, hetzner_status: null, hetzner_id: null })),
    };
  }
}

function scanLabProtocols(): Array<{
  filename: string;
  bytes: number;
  projection_audit_hint: string;
  substrate_backing_hint: string;
  inchikey_anchor_hint: string;
}> {
  const dir = path.join(process.cwd(), "data", "lab_protocols");
  if (!fs.existsSync(dir)) return [];
  const out: Array<{
    filename: string;
    bytes: number;
    projection_audit_hint: string;
    substrate_backing_hint: string;
    inchikey_anchor_hint: string;
  }> = [];
  for (const filename of fs.readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    const fp = path.join(dir, filename);
    const raw = fs.readFileSync(fp, "utf8");
    const lower = raw.toLowerCase();
    const hasInchi = /\binchi\s*key\b|inchikey/i.test(raw);
    const hasProjection = lower.includes("projection") || lower.includes("s4") || lower.includes("c4");
    const hasVerify = lower.includes("verify") || lower.includes("witness") || lower.includes("substrate");
    out.push({
      filename,
      bytes: Buffer.byteLength(raw, "utf8"),
      projection_audit_hint: hasProjection && hasVerify ? "DOCUMENT_LISTS_PROJECTION_PATH" : "REVIEW_REQUIRED",
      substrate_backing_hint: lower.includes("ingest") || lower.includes("mcp") ? "INGEST_PATH_DOCUMENTED" : "S4_DRAFT_UNTIL_INGESTED",
      inchikey_anchor_hint: hasInchi ? "MENTIONED_IN_TEXT" : "NO_INCHIKEY_LITERAL",
    });
  }
  return out.sort((a, b) => a.filename.localeCompare(b.filename));
}

export async function GET() {
  const health = await gatewayGet("/health");
  const healthJson = health.json as Record<string, unknown> | null;

  const claimsRecent = await gatewayGet("/claims?limit=1000");
  const claimsRaw = Array.isArray(claimsRecent.json) ? claimsRecent.json : [];
  const claims = claimsRaw as Record<string, unknown>[];

  const markerFromDb: Record<string, unknown>[] = [];
  for (const needle of RECEIPT_MARKERS) {
    const mr = await gatewayQuery(
      `FOR c IN mcp_claims FILTER CONTAINS(TO_STRING(c), @needle) SORT c.created_at DESC LIMIT 40 RETURN c`,
      { needle }
    );
    if (mr.ok) markerFromDb.push(...(mr.rows as Record<string, unknown>[]));
  }

  const closed = claims.filter((c) => isClosedStatus(statusStr(c)));
  const markerHits = claims.filter((c) => claimHasReceiptMarker(c));
  const receiptMap = new Map<string, Record<string, unknown>>();
  for (const c of [...markerFromDb, ...markerHits, ...closed]) {
    const k = claimDedupeKey(c);
    if (k) receiptMap.set(k, c);
  }
  const receipt_wall = Array.from(receiptMap.values())
    .sort((a, b) => claimTime(b) - claimTime(a))
    .slice(0, 80);

  const openLoops = claims
    .filter((c) => isOpenStatus(statusStr(c)))
    .sort((a, b) => claimTime(a) - claimTime(b))
    .slice(0, 80)
    .map((c) => ({ ...c, age_days: ageDays(c) }));

  const metrics = await gatewayQuery(`RETURN {
    claims: LENGTH(FOR x IN mcp_claims RETURN 1),
    envelopes: LENGTH(FOR x IN truth_envelopes RETURN 1)
  }`);
  const metricRow =
    metrics.ok && metrics.rows[0] && typeof metrics.rows[0] === "object"
      ? (metrics.rows[0] as Record<string, number>)
      : { claims: 0, envelopes: 0 };

  /** All game rooms seen in substrate + baseline list */
  const roomRollup = await gatewayQuery(
    `FOR c IN mcp_claims
      FILTER c.payload != null AND HAS(c.payload, "game_room") AND c.payload.game_room != null
      COLLECT room = c.payload.game_room WITH COUNT INTO cnt
      RETURN { room, count: cnt }`
  );
  const rollRows = roomRollup.ok ? (roomRollup.rows as { room: string; count: number }[]) : [];
  const roomSet = new Set<string>([...GAME_ROOMS_BASE, ...rollRows.map((x) => x.room)]);

  const game_room_counts: Record<string, number> = {};
  for (const r of rollRows) game_room_counts[r.room] = r.count;
  for (const r of GAME_ROOMS_BASE) if (game_room_counts[r] == null) game_room_counts[r] = 0;

  const gameRoomFeeds: Record<string, Record<string, unknown>[]> = {};
  const roomList = Array.from(roomSet).sort();
  await Promise.all(
    roomList.map(async (room) => {
      const r = await gatewayQuery(
        `FOR c IN mcp_claims
          FILTER c.payload != null AND HAS(c.payload, "game_room") AND c.payload.game_room == @room
          SORT c.created_at DESC
          LIMIT 400
          RETURN c`,
        { room }
      );
      gameRoomFeeds[room] = r.ok ? (r.rows as Record<string, unknown>[]) : [];
    })
  );

  /** Fallback: substring filter catches legacy rows without structured game_room */
  for (const room of GAME_ROOMS_BASE) {
    if ((gameRoomFeeds[room]?.length ?? 0) > 0) continue;
    const r = await gatewayGet(`/claims?filter=${encodeURIComponent(room)}&limit=400`);
    gameRoomFeeds[room] = Array.isArray(r.json) ? (r.json as Record<string, unknown>[]) : [];
  }

  const discoveredNames = await listDiscoveredCollectionNames();
  const discovery_by_collection: Record<
    string,
    { count: number; sample: ReturnType<typeof normalizeDiscoveryRow>[]; error?: string }
  > = {};

  await Promise.all(
    discoveredNames.map(async (colName) => {
      try {
        const cntQ = await gatewayQuery(`RETURN LENGTH(FOR x IN @@c RETURN 1)`, { "@c": colName });
        const count =
          cntQ.ok && typeof cntQ.rows[0] === "number" ? (cntQ.rows[0] as number) : 0;
        const sampQ = await gatewayQuery(
          `FOR d IN @@c
            LIMIT 120
            RETURN d`,
          { "@c": colName }
        );
        const raw = sampQ.ok ? (sampQ.rows as Record<string, unknown>[]) : [];
        discovery_by_collection[colName] = {
          count,
          sample: raw.map((d) => normalizeDiscoveryRow(colName, d)),
        };
        if (!sampQ.ok) discovery_by_collection[colName].error = "sample_query_failed";
      } catch (e) {
        discovery_by_collection[colName] = { count: 0, sample: [], error: String(e) };
      }
    })
  );

  /** INV3 protein anchors always merged into manifest sample */
  const inv3Q = await gatewayQuery(
    `FOR d IN discovered_proteins
      FILTER d.source == "inv3_recursive_repair" OR d.inv3_recursive_repair == true
      RETURN d`
  );
  if (inv3Q.ok && discovery_by_collection.discovered_proteins) {
    const inv3Rows = inv3Q.rows as Record<string, unknown>[];
    const keys = new Set(discovery_by_collection.discovered_proteins.sample.map((s) => String(s._key)));
    for (const d of inv3Rows) {
      if (keys.has(String(d._key))) continue;
      keys.add(String(d._key));
      discovery_by_collection.discovered_proteins.sample.push(normalizeDiscoveryRow("discovered_proteins", d));
    }
  }

  const inv3MolQ = await gatewayQuery(
    `FOR d IN discovered_molecules
      FILTER d.name == "AML-CHEM-001" OR d.molecule_id == "AML-CHEM-001" OR d.compound_id == "AML-CHEM-001"
      LIMIT 5
      RETURN d`
  );
  if (inv3MolQ.ok && discovery_by_collection.discovered_molecules) {
    const rows = inv3MolQ.rows as Record<string, unknown>[];
    const keys = new Set(discovery_by_collection.discovered_molecules.sample.map((s) => String(s._key)));
    for (const d of rows) {
      if (keys.has(String(d._key))) continue;
      keys.add(String(d._key));
      discovery_by_collection.discovered_molecules.sample.push(normalizeDiscoveryRow("discovered_molecules", d));
    }
  }

  const discovery_manifest: ReturnType<typeof normalizeDiscoveryRow>[] = [];
  for (const col of discoveredNames.sort()) {
    discovery_manifest.push(...(discovery_by_collection[col]?.sample ?? []));
  }

  const knightFlat = discovery_manifest.filter((d) => {
    const ac = String(d.assumption_class ?? "");
    const blob = JSON.stringify(d).toLowerCase();
    return ac === "HYPOTHESIS" || blob.includes("candidate") || blob.includes("knight");
  });

  /** Materials: top 10 per domain + totals (full-table scan once). */
  let materials_by_domain: Array<{
    domain: string;
    total: number;
    top_10: Array<Record<string, unknown>>;
  }> = [];
  let materials_error: string | null = null;
  let materials_grand_total = 0;
  const matTotalQ = await gatewayQuery(`RETURN LENGTH(FOR x IN discovered_materials RETURN 1)`);
  if (matTotalQ.ok && typeof matTotalQ.rows[0] === "number") {
    materials_grand_total = matTotalQ.rows[0] as number;
  }
  const matAgg = await gatewayQuery(
    `FOR d IN discovered_materials
      LET dom = (HAS(d, "domain") AND d.domain != null AND d.domain != "" ? d.domain : "unspecified")
      COLLECT domain = dom INTO g = d
      LET top_10 = (
        FOR x IN g
          LET fs = x.fot_score != null ? x.fot_score : (HAS(x, "original_data") && x.original_data != null && HAS(x.original_data, "fot_score") ? x.original_data.fot_score : null)
          SORT fs DESC
          LIMIT 10
          RETURN {
            compound_id: x.compound_id || x.name || x._key,
            fot_score: fs,
            domain: x.domain,
            inchikey: x.inchikey,
            _key: x._key,
            metrics: {
              conductivity: x.conductivity,
              band_gap: x.band_gap,
              density: x.density,
              tc: x.tc,
              z_t: x.z_t
            }
          }
      )
      RETURN { domain, total: LENGTH(g), top_10 }`
  );
  if (matAgg.ok && Array.isArray(matAgg.rows)) {
    materials_by_domain = matAgg.rows as typeof materials_by_domain;
    materials_by_domain.sort((a, b) => b.total - a.total);
  } else {
    materials_error = "materials_domain_aggregation_failed";
  }

  const mcpClaimsFeed = await gatewayQuery(
    `FOR c IN mcp_claims
      SORT c.created_at DESC
      LIMIT 600
      RETURN MERGE(
        UNSET(c, "embedding", "vectors"),
        { payload_preview: SUBSTRING(TO_STRING(c.payload), 0, 520) }
      )`
  );

  const lab_protocols = scanLabProtocols();
  const mesh_hetzner = await hetznerMeshStatus();
  const mesh_heartbeat_registry = await meshHeartbeatRegistry();

  const payload = {
    generated_at: new Date().toISOString(),
    gateway: { ok: health.ok, status: health.status, body: healthJson },
    panels: {
      receipt_wall,
      discovery_manifest,
      discovery_index: discoveredNames.map((n) => ({
        collection: n,
        count: discovery_by_collection[n]?.count ?? 0,
        sample_size: discovery_by_collection[n]?.sample.length ?? 0,
        error: discovery_by_collection[n]?.error,
      })),
      discovery_by_collection,
      knight_candidate_signals: knightFlat,
      open_loops: openLoops,
      game_room_feeds: gameRoomFeeds,
      game_room_counts,
      game_room_list: roomList,
      game_room_pagination_note:
        "Use GET /api/sovereign-mesh/game-room?room=&offset=&limit= for full substrate history per room.",
      materials_by_domain,
      materials_grand_total,
      materials_error,
      mcp_claims_feed: mcpClaimsFeed.ok ? (mcpClaimsFeed.rows as Record<string, unknown>[]) : [],
      lab_protocols,
      mesh_health: {
        gateway_status: healthJson?.status,
        nats_connected: healthJson?.nats_connected,
        claim_count_query: metricRow.claims,
        envelope_count_query: metricRow.envelopes,
        claims_fetch_ok: claimsRecent.ok,
      },
      mesh_cells: mesh_hetzner,
      mesh_heartbeat_registry,
    },
  };

  return NextResponse.json(payload);
}
