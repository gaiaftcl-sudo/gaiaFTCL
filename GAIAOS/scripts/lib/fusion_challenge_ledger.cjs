/**
 * Single source for fusion challenge ledger file (teams + monotonic revenue).
 * Used by Next POST /api/fusion/challenge-ledger and optional CLI / NATS consumer.
 */
const fs = require("fs");
const path = require("path");

const SCHEMA = "gaiaftcl_fusion_challenge_ledger_hint_v1";

function ledgerPath(root) {
  return path.join(root, "evidence", "fusion_control", "fusion_challenge_ledger_receipt.json");
}

function readLedger(root) {
  try {
    const raw = fs.readFileSync(ledgerPath(root), "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function ensureDoc(root, prev) {
  if (prev && prev.schema === SCHEMA) {
    if (!Array.isArray(prev.registered_teams)) prev.registered_teams = [];
    return prev;
  }
  return {
    schema: SCHEMA,
    ts_utc: new Date().toISOString(),
    cumulative_revenue_eur: 0,
    teams_moored_reported: 0,
    registered_teams: [],
    source: "fusion_challenge_ledger",
  };
}

function writeDoc(root, doc) {
  const p = ledgerPath(root);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  doc.ts_utc = new Date().toISOString();
  fs.writeFileSync(p, JSON.stringify(doc, null, 2), "utf8");
  return doc;
}

/**
 * @param {string} root GAIA_ROOT
 * @param {{ team_id: string, hub_id?: string|null, note?: string|null, source?: string }} payload
 */
function registerTeam(root, payload) {
  const team_id = String(payload.team_id || "").trim();
  if (!team_id) {
    const e = new Error("team_id required");
    e.code = "VALIDATION";
    throw e;
  }
  const doc = ensureDoc(root, readLedger(root));
  const teams = doc.registered_teams;
  if (teams.some((t) => t.team_id === team_id)) {
    return { ok: true, duplicate: true, doc };
  }
  teams.push({
    team_id,
    hub_id: payload.hub_id != null ? String(payload.hub_id) : null,
    note: payload.note != null ? String(payload.note) : null,
    registered_at_utc: new Date().toISOString(),
    source: payload.source ? String(payload.source) : "ledger",
  });
  doc.teams_moored_reported = teams.length;
  writeDoc(root, doc);
  return { ok: true, duplicate: false, doc };
}

/**
 * Monotonic revenue only (treasury witness).
 * @param {string} root
 * @param {{ cumulative_revenue_eur: number, note?: string|null, source?: string }} payload
 */
function setRevenue(root, payload) {
  const next = Number(payload.cumulative_revenue_eur);
  if (!Number.isFinite(next) || next < 0) {
    const e = new Error("cumulative_revenue_eur must be a non-negative finite number");
    e.code = "VALIDATION";
    throw e;
  }
  const doc = ensureDoc(root, readLedger(root));
  const prev = Number(doc.cumulative_revenue_eur);
  const base = Number.isFinite(prev) ? prev : 0;
  if (next < base) {
    const e = new Error(`revenue not monotonic: ${next} < ${base}`);
    e.code = "REFUSED";
    throw e;
  }
  doc.cumulative_revenue_eur = next;
  if (payload.note != null) doc.revenue_note = String(payload.note);
  if (payload.source) doc.revenue_source = String(payload.source);
  writeDoc(root, doc);
  return { ok: true, doc };
}

/**
 * @param {string} root
 * @param {{ op: string } & Record<string, unknown>} body
 */
function applyLedgerOp(root, body) {
  if (!body || typeof body !== "object") {
    const e = new Error("body required");
    e.code = "VALIDATION";
    throw e;
  }
  const op = String(body.op || "").trim();
  if (op === "register_team") {
    return registerTeam(root, {
      team_id: body.team_id,
      hub_id: body.hub_id,
      note: body.note,
      source: body.source,
    });
  }
  if (op === "set_revenue") {
    return setRevenue(root, {
      cumulative_revenue_eur: body.cumulative_revenue_eur,
      note: body.note,
      source: body.source,
    });
  }
  const e = new Error('op must be "register_team" or "set_revenue"');
  e.code = "VALIDATION";
  throw e;
}

module.exports = {
  SCHEMA,
  ledgerPath,
  readLedger,
  registerTeam,
  setRevenue,
  applyLedgerOp,
};
