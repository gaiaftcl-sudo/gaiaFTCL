/**
 * CLI soak aggregation for fusion_soak_report.sh (Node require).
 * Next.js uses services/gaiaos_ui_web/app/lib/fusionS4SoakSummary.ts — keep logic aligned when changing either.
 */
async function buildSoakSummary(gaiaRoot) {
  const fs = require("fs/promises");
  const path = require("path");
  const ev = path.join(gaiaRoot, "evidence", "fusion_control");
  const jsonl = path.join(ev, "long_run_signals.jsonl");
  const lastReceipt = path.join(ev, "last_control_matrix_receipt.json");
  const viol = path.join(ev, "soak_violations.jsonl");
  const pcssp = path.join(ev, "pcssp_fault_receipts.jsonl");
  const torax = path.join(ev, "torax_episode_metrics.jsonl");

  async function tailLines(file, maxLines) {
    try {
      const stat = await fs.stat(file);
      if (stat.size === 0) return [];
      const chunk = Math.min(stat.size, 768 * 1024);
      const fh = await fs.open(file, "r");
      const buf = Buffer.alloc(chunk);
      await fh.read(buf, 0, chunk, stat.size - chunk);
      await fh.close();
      return buf
        .toString("utf8")
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean)
        .slice(-maxLines);
    } catch {
      return [];
    }
  }

  function parseLine(line) {
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  }

  function isMetalReceipt(o) {
    if (!o || typeof o !== "object") return false;
    if (o.schema === "fusion_control_batch_receipt_v1") return true;
    if (o.validation_engine === "gpu_fused_multicycle" || o.validation_engine === "per_cycle_gpu_sync")
      return typeof o.wall_time_ms === "number" || typeof o.wall_time_ms === "string";
    return false;
  }

  const lines = await tailLines(jsonl, 12000);
  const metal = [];
  for (const line of lines) {
    const o = parseLine(line);
    if (!o) continue;
    if (isMetalReceipt(o)) {
      metal.push(o);
      continue;
    }
    if (o.control_signal === "fusion_cell_batch" && isMetalReceipt(o)) {
      metal.push(o);
    }
  }

  const wall = metal
    .map((r) => Number(r.wall_time_ms))
    .filter((n) => Number.isFinite(n));
  const emax = metal
    .map((r) => Number(r.worst_max_abs_error))
    .filter((n) => Number.isFinite(n));
  const cycles = metal.map((r) => Number(r.cycles_completed)).filter((n) => Number.isFinite(n));

  const sortedW = [...wall].sort((a, b) => a - b);
  const p50 = sortedW.length ? sortedW[Math.floor(sortedW.length * 0.5)] : null;

  let violCount = 0;
  try {
    const vlines = await tailLines(viol, 50000);
    violCount = vlines.filter((l) => l.includes("fusion_soak_violation_v1")).length;
  } catch {
    violCount = 0;
  }

  let pcsspLines = [];
  try {
    pcsspLines = await tailLines(pcssp, 5000);
  } catch {
    pcsspLines = [];
  }
  const pcsspRecs = pcsspLines.map(parseLine).filter(Boolean);
  const pcsspRefused = pcsspRecs.filter((r) => r.terminal === "REFUSED" || r.c4_terminal === "REFUSED");
  const pcsspLat = pcsspRecs
    .map((r) => Number(r.latency_ms))
    .filter((n) => Number.isFinite(n));

  let toraxLines = [];
  try {
    toraxLines = await tailLines(torax, 20000);
  } catch {
    toraxLines = [];
  }
  const toraxRecs = toraxLines.map(parseLine).filter(Boolean);
  const dh = toraxRecs
    .map((r) => Number(r.delta_h ?? r.delta_H))
    .filter((n) => Number.isFinite(n));

  let lastRec = null;
  try {
    const raw = await fs.readFile(lastReceipt, "utf8");
    lastRec = JSON.parse(raw);
  } catch {
    lastRec = null;
  }

  const firstTs = metal[0]?.ts ?? metal[0]?.ts_utc ?? null;
  const lastM = metal[metal.length - 1];
  const lastTs = lastM?.ts ?? lastM?.ts_utc ?? null;
  const sigWall = lastM != null ? Number(lastM.wall_time_ms) : NaN;
  const sigGpu = lastM != null ? Number(lastM.gpu_wall_us) : NaN;
  const sigE = lastM != null ? Number(lastM.worst_max_abs_error) : NaN;
  const sigCyc = lastM != null ? Number(lastM.cycles_completed) : NaN;

  return {
    schema: "gaiaftcl_fusion_soak_summary_ui_v1",
    gaia_root: gaiaRoot,
    jsonl_path: jsonl,
    jsonl_paths: {
      long_run_signals: jsonl,
      soak_violations: viol,
      pcssp_fault_receipts: pcssp,
      torax_episode_metrics: torax,
    },
    soak_violations_file: {
      jsonl_path: viol,
      violation_lines: violCount,
    },
    nstxu_metal: {
      batch_rows_in_window: metal.length,
      total_cycles_in_window: cycles.reduce((a, b) => a + b, 0),
      wall_time_ms_min: wall.length ? Math.min(...wall) : null,
      wall_time_ms_max: wall.length ? Math.max(...wall) : null,
      wall_time_ms_p50: p50,
      worst_max_abs_error_max: emax.length ? Math.max(...emax) : null,
      soak_violation_lines: violCount,
      first_ts: firstTs,
      last_ts: lastTs,
      signals_last_wall_ms: Number.isFinite(sigWall) ? sigWall : null,
      signals_last_gpu_wall_us: Number.isFinite(sigGpu) ? sigGpu : null,
      signals_last_worst_emax: Number.isFinite(sigE) ? sigE : null,
      signals_last_cycles_completed: Number.isFinite(sigCyc) ? sigCyc : null,
      last_receipt_wall_ms: lastRec && Number.isFinite(Number(lastRec.wall_time_ms)) ? Number(lastRec.wall_time_ms) : null,
      last_receipt_worst_emax:
        lastRec && Number.isFinite(Number(lastRec.worst_max_abs_error))
          ? Number(lastRec.worst_max_abs_error)
          : null,
      metallib: typeof lastRec?.metallib === "string" ? lastRec.metallib : null,
    },
    pcssp_faults: {
      receipt_rows: pcsspRecs.length,
      refused_count: pcsspRefused.length,
      latency_ms_max: pcsspLat.length ? Math.max(...pcsspLat) : null,
      latency_ms_min: pcsspLat.length ? Math.min(...pcsspLat) : null,
    },
    torax_episodes: {
      rows: toraxRecs.length,
      delta_h_last: dh.length ? dh[dh.length - 1] : null,
      delta_h_min: dh.length ? Math.min(...dh) : null,
      delta_h_max: dh.length ? Math.max(...dh) : null,
    },
  };
}

function formatSoakMarkdown(s) {
  const m = s.nstxu_metal;
  const v = s.soak_violations_file;
  const p = s.pcssp_faults;
  const t = s.torax_episodes;
  let gitSha = "—";
  try {
    const { execSync } = require("child_process");
    gitSha = execSync("git rev-parse HEAD", { encoding: "utf8", cwd: s.gaia_root }).trim();
  } catch {
    /* optional */
  }
  const lines = [
    "# FUSION_SOAK_TEST_REPORT",
    "",
    `Generated: ${new Date().toISOString()}`,
    `Schema: ${s.schema}`,
    `GAIA_ROOT: \`${s.gaia_root}\``,
    `git HEAD: \`${gitSha}\``,
    "",
    "## NSTX-U / Metal (window tail)",
    "",
    "| Field | Value |",
    "| --- | --- |",
    `| JSONL | \`${s.jsonl_path}\` |`,
    `| batch rows (window) | ${m.batch_rows_in_window} |`,
    `| total cycles (sum in window) | ${m.total_cycles_in_window} |`,
    `| wall_time_ms min / p50 / max | ${m.wall_time_ms_min ?? "—"} / ${m.wall_time_ms_p50 ?? "—"} / ${m.wall_time_ms_max ?? "—"} |`,
    `| worst ε max in window | ${m.worst_max_abs_error_max ?? "—"} |`,
    `| last signals tail τ_wall / τ_gpu_us / ε / cycles | ${m.signals_last_wall_ms ?? "—"} / ${m.signals_last_gpu_wall_us ?? "—"} / ${m.signals_last_worst_emax ?? "—"} / ${m.signals_last_cycles_completed ?? "—"} |`,
    `| first_ts / last_ts | ${m.first_ts ?? "—"} / ${m.last_ts ?? "—"} |`,
    `| last_control_matrix (sidecar, not table row) wall_ms / ε | ${m.last_receipt_wall_ms ?? "—"} / ${m.last_receipt_worst_emax ?? "—"} |`,
    "",
    "## Soak violations JSONL",
    "",
    `| JSONL | \`${v.jsonl_path}\` |`,
    `| fusion_soak_violation_v1 lines (tail) | ${v.violation_lines} |`,
    "",
    "## PCSSP fault receipts",
    "",
    `| receipt_rows | ${p.receipt_rows} |`,
    `| refused_count | ${p.refused_count} |`,
    `| latency_ms min / max | ${p.latency_ms_min ?? "—"} / ${p.latency_ms_max ?? "—"} |`,
    "",
    "## TORAX episode metrics",
    "",
    `| rows | ${t.rows} |`,
    `| ΔH min / max / last | ${t.delta_h_min ?? "—"} / ${t.delta_h_max ?? "—"} / ${t.delta_h_last ?? "—"} |`,
    "",
    "## Cycle scaling",
    "",
    "Inner batch size: `FUSION_VALIDATION_CYCLES`. Up to 100,000 per batch by default; set `FUSION_ALLOW_HIGH_CYCLES=1` for up to 1,000,000 per `fusion_control` invocation.",
    "",
  ];
  return lines.join("\n");
}

module.exports = { buildSoakSummary, formatSoakMarkdown };
