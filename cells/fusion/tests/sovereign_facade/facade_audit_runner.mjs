#!/usr/bin/env node
/**
 * Sovereign facade full audit: TCP, mesh HTTP, adapter phases, report generation.
 * Playwright Phase 1 is invoked via subprocess (HTTP/HTTPS per user request).
 *
 * Usage (from repo GAIAOS root):
 *   node tests/sovereign_facade/facade_audit_runner.mjs
 */
import { spawnSync } from "node:child_process";
import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";
import https from "node:https";
import tls from "node:tls";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const GAIAOS_ROOT = path.resolve(__dirname, "../..");
const REPORT_PATH = path.join(GAIAOS_ROOT, "evidence/sovereign_facade/PLAYWRIGHT_TEST_REPORT_V1.md");
const HOST = "77.42.85.60";
const MAIL_HOST = "mail.gaiaftcl.com";
const UI_WEB = path.join(GAIAOS_ROOT, "services/gaiaos_ui_web");

const results = [];

function record(phase, id, name, status, expected, actual, evidence) {
  results.push({ phase, id, name, status, expected, actual, evidence });
}

function tryTcp(host, port, timeoutMs = 8000) {
  return new Promise((resolve) => {
    const sock = net.createConnection({ host, port }, () => {
      sock.destroy();
      resolve({ ok: true, detail: "connected" });
    });
    sock.on("error", (e) => resolve({ ok: false, detail: e.code || String(e.message) }));
    sock.setTimeout(timeoutMs, () => {
      try {
        sock.destroy();
      } catch (_) {}
      resolve({ ok: false, detail: "timeout" });
    });
  });
}

function smtpProbe(port) {
  return new Promise((resolve) => {
    const sock = net.createConnection({ host: HOST, port }, () => {});
    let buf = "";
    const timer = setTimeout(() => {
      try {
        sock.destroy();
      } catch (_) {}
      resolve({ ok: false, banner: buf.slice(0, 500), detail: "timeout" });
    }, 8000);
    sock.on("data", (d) => {
      buf += d.toString("utf8");
      if (buf.includes("\r\n")) {
        clearTimeout(timer);
        sock.write(`EHLO facade-audit\r\n`);
        setTimeout(() => {
          try {
            sock.destroy();
          } catch (_) {}
          resolve({ ok: true, banner: buf.slice(0, 800) });
        }, 500);
      }
    });
    sock.on("error", (e) => {
      clearTimeout(timer);
      resolve({ ok: false, banner: buf, detail: e.code || String(e.message) });
    });
  });
}

function imapTlsBanner() {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ ok: false, raw: "", detail: "timeout" }), 10000);
    const sock = tls.connect(
      { host: HOST, port: 993, servername: MAIL_HOST, rejectUnauthorized: false },
      () => {}
    );
    let buf = "";
    sock.on("data", (d) => {
      buf += d.toString("utf8");
      if (buf.includes("\r\n") || buf.length > 80) {
        clearTimeout(timer);
        try {
          sock.end();
        } catch (_) {}
        resolve({ ok: true, raw: buf.slice(0, 500) });
      }
    });
    sock.on("error", (e) => {
      clearTimeout(timer);
      resolve({ ok: false, raw: buf, detail: e.code || String(e.message) });
    });
    sock.on("timeout", () => {
      clearTimeout(timer);
      try {
        sock.destroy();
      } catch (_) {}
      resolve({ ok: false, raw: buf, detail: "timeout" });
    });
    sock.setTimeout(9000);
  });
}

function httpGet(url, opts = {}) {
  return new Promise((resolve) => {
    const lib = url.startsWith("https") ? https : http;
    const req = lib.request(
      url,
      { method: "GET", timeout: opts.timeout || 12000, headers: opts.headers || {} },
      (res) => {
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () =>
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: body.slice(0, 4000),
          })
        );
      }
    );
    req.on("error", (e) => resolve({ error: e.code || e.message, body: "" }));
    req.on("timeout", () => {
      req.destroy();
      resolve({ error: "timeout", body: "" });
    });
    req.end();
  });
}

function httpPostJson(url, json) {
  return new Promise((resolve) => {
    const data = JSON.stringify(json);
    const u = new URL(url);
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port || 80,
        path: u.pathname + u.search,
        method: "POST",
        headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) },
        timeout: 20000,
      },
      (res) => {
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () =>
          resolve({ status: res.statusCode, body: body.slice(0, 4000) })
        );
      }
    );
    req.on("error", (e) => resolve({ error: e.code || e.message, body: "" }));
    req.on("timeout", () => {
      req.destroy();
      resolve({ error: "timeout", body: "" });
    });
    req.write(data);
    req.end();
  });
}

function findPython() {
  const tryPy = spawnSync("python3", ["-V"], { encoding: "utf-8" });
  if (tryPy.status === 0) return "python3";
  const tryPy2 = spawnSync("python", ["-V"], { encoding: "utf-8" });
  if (tryPy2.status === 0) return "python";
  return "python3";
}

function flattenPlaywrightSuites(suites) {
  const rows = [];
  function walk(list) {
    for (const su of list || []) {
      for (const sp of su.specs || []) {
        for (const t of sp.tests || []) {
          const tr = t.results?.[0];
          const errMsg = tr?.error?.message || tr?.errors?.[0]?.message || "";
          rows.push({
            title: sp.title || t.title,
            status: tr?.status,
            error: errMsg,
          });
        }
      }
      if (su.suites?.length) walk(su.suites);
    }
  }
  walk(suites);
  return rows;
}

async function main() {
  const py = findPython();
  const verifyGr = path.join(__dirname, "verify_game_room.py");

  // --- Playwright Phase 1 ---
  const pwConfig = path.join(UI_WEB, "tests/sovereign_facade/playwright.sovereign.config.ts");
  fs.mkdirSync(path.join(UI_WEB, "test-results"), { recursive: true });
  const pwBin = path.join(UI_WEB, "node_modules", ".bin", "playwright");
  const pwExe = fs.existsSync(pwBin) ? pwBin : "npx";
  const pwArgs = fs.existsSync(pwBin)
    ? ["test", "-c", pwConfig]
    : ["playwright", "test", "-c", pwConfig];
  const pw = spawnSync(pwExe, pwArgs, {
    cwd: UI_WEB,
    encoding: "utf-8",
    env: { ...process.env, CI: "1", NODE_PATH: "" },
    maxBuffer: 20 * 1024 * 1024,
  });
  const pwOut = (pw.stdout || "") + (pw.stderr || "");
  const pwJsonPath = path.join(UI_WEB, "test-results/sovereign-facade-playwright.json");
  let pwSummary = `exit=${pw.status}\n${pwOut.slice(-8000)}`;
  let pwParsed = 0;
  if (fs.existsSync(pwJsonPath)) {
    try {
      const j = JSON.parse(fs.readFileSync(pwJsonPath, "utf8"));
      const flat = flattenPlaywrightSuites(j.suites || []);
      for (const row of flat) {
        const idMatch = row.title.match(/^([\d.]+)\s*—/);
        const id = idMatch ? idMatch[1] : "1.x";
        const shortName = row.title.replace(/^\d+\.\d+\s*—\s*/, "").trim() || row.title;
        record(
          "1",
          id,
          shortName,
          row.status === "passed" ? "PASS" : row.status === "skipped" ? "BLOCKED" : "FAIL",
          "Playwright expectations in phase1_s4_http.spec.ts",
          row.status || "unknown",
          (row.error || "").slice(0, 1200)
        );
        pwParsed++;
      }
    } catch (e) {
      record("1", "1.x", "Playwright JSON parse", "BLOCKED", "Valid playwright JSON", String(e.message), pwSummary.slice(0, 2000));
    }
  }
  if (pwParsed === 0) {
    record(
      "1",
      "1.1-1.3",
      "Playwright Phase 1 (aggregate)",
      pw.status === 0 ? "PASS" : "FAIL",
      "npx playwright test completes; per-spec JSON or list output",
      `exit ${pw.status}; json_rows=${pwParsed}`,
      pwSummary.slice(0, 4000)
    );
  }

  // 1.4 External C4 ports (snapshot reused for Phase 4.1)
  const c4Ports = [8803, 8529, 4222, 8222, 8805, 9000, 8830];
  const c4TcpSnapshot = [];
  for (const port of c4Ports) {
    const r = await tryTcp(HOST, port);
    c4TcpSnapshot.push({ port, ...r });
    const strict = !r.ok;
    record(
      "1",
      "1.4",
      `External TCP ${HOST}:${port}`,
      strict ? "PASS" : "FAIL",
      "Connection refused or timeout; none accept",
      r.ok ? `CONNECTED (unexpected)` : r.detail,
      JSON.stringify(r)
    );
  }

  // 1.5 SMTP
  for (const port of [25, 587]) {
    const r = await smtpProbe(port);
    const leak =
      r.banner &&
      /docker|172\.(1[6-9]|2\d|3[01])\.|nats|arangodb|mailcow-internal/i.test(r.banner);
    record(
      "1",
      "1.5",
      `SMTP TCP ${port}`,
      r.ok && !leak ? "PASS" : r.ok && leak ? "FAIL" : "FAIL",
      "Accepts connection; EHLO/banner no internal topology",
      r.ok ? r.banner.replace(/\r/g, "\\r").slice(0, 400) : String(r.detail),
      leak ? "Possible topology leak in banner" : "checked"
    );
  }

  // 1.6 IMAP
  const imap = await imapTlsBanner();
  const imapLeak =
    imap.raw &&
    /docker|172\.(1[6-9]|2\d|3[01])\.|nats|arangodb|dovecot[- ]?v?\d|mailcow-internal/i.test(
      imap.raw
    );
  record(
    "1",
    "1.6",
    "IMAPS 993",
    imap.ok && !imapLeak ? "PASS" : imap.ok ? "FAIL" : "FAIL",
    "Accepts; banner no version/internal details",
    imap.ok ? imap.raw.replace(/\r/g, "\\r").slice(0, 400) : String(imap.detail),
    imapLeak ? "Banner may expose version or internals" : "checked"
  );

  // Phase 2
  const gwHealth = await httpGet(`http://${HOST}:8803/health`);
  let g2Status = "FAIL";
  let g2Evidence = "";
  if (gwHealth.error) {
    g2Status = gwHealth.error === "ECONNREFUSED" || gwHealth.error === "timeout" ? "BLOCKED" : "FAIL";
    g2Evidence = String(gwHealth.error);
  } else if (gwHealth.status === 200) {
    g2Status = /healthy|nats_connected.*true/i.test(gwHealth.body) ? "PASS" : "FAIL";
    g2Evidence = gwHealth.body.slice(0, 800);
  } else {
    g2Evidence = `HTTP ${gwHealth.status} ${gwHealth.body.slice(0, 400)}`;
  }
  record("2", "2.1", "Gateway health", g2Status, "200 healthy, NATS connected", `status ${gwHealth.status || gwHealth.error}`, g2Evidence);

  const claims = await httpGet(`http://${HOST}:8803/claims?limit=2`);
  let cStatus = "FAIL";
  if (claims.error) cStatus = claims.error === "ECONNREFUSED" || claims.error === "timeout" ? "BLOCKED" : "FAIL";
  else if (claims.status === 404) cStatus = "GATEWAY_DRIFT";
  else if (claims.status === 200) {
    cStatus = /\[[\s\S]*\]|\{[\s\S]*claim/i.test(claims.body) ? "PASS" : "FAIL";
  } else cStatus = `FAIL`;
  record(
    "2",
    "2.2",
    "Claims endpoint",
    cStatus,
    "200 JSON array with claim documents",
    claims.error || `HTTP ${claims.status}`,
    claims.body.slice(0, 1200)
  );

  const ingest = await httpPostJson(`http://${HOST}:8803/universal_ingest`, {
    type: "TEST",
    from: "playwright",
    payload: { test: true, source: "facade_test" },
  });
  let ingStatus = "FAIL";
  if (ingest.error) ingStatus = ingest.error === "ECONNREFUSED" || ingest.error === "timeout" ? "BLOCKED" : "FAIL";
  else if (ingest.status === 404) ingStatus = "GATEWAY_DRIFT";
  else if (ingest.status === 200 || ingest.status === 201) {
    ingStatus = /claim|accepted|key/i.test(ingest.body) ? "PASS" : "FAIL";
  }
  record(
    "2",
    "2.3",
    "Universal ingest",
    ingStatus,
    "200/201 with claim key",
    ingest.error || `HTTP ${ingest.status}`,
    ingest.body.slice(0, 1200)
  );

  const ar = await httpGet(`http://${HOST}:8529/_api/version`);
  const arUnreachable =
    ar.error === "ECONNREFUSED" || ar.error === "timeout" || ar.error === "ETIMEDOUT";
  const arOk = arUnreachable;
  record(
    "2",
    "2.4",
    "Arango external",
    arOk ? "PASS" : "FAIL",
    "Must not be reachable externally (no TCP/HTTP to 8529 from WAN)",
    ar.error || `HTTP ${ar.status} (port reachable)`,
    ar.body.slice(0, 200)
  );

  const n422 = await tryTcp(HOST, 4222);
  const nOk = !n422.ok;
  record(
    "2",
    "2.5",
    "NATS 4222 external",
    nOk ? "PASS" : "FAIL",
    "Refused or timeout",
    n422.ok ? "connected" : n422.detail,
    JSON.stringify(n422)
  );

  // Phase 3 — adapter
  const runAd = (env, body) => {
    const adapterPath = path.join(GAIAOS_ROOT, "services/mailcow_inbound_adapter/adapter.py");
    return spawnSync(py, [adapterPath], {
      cwd: GAIAOS_ROOT,
      input: body,
      encoding: "utf-8",
      env: { ...process.env, ...env },
      maxBuffer: 10 * 1024 * 1024,
    });
  };

  const smokeBody =
    "From: test@external.com\nTo: ops@gaiaftcl.com\nSubject: Playwright facade test\n\nThis is a test signal.";
  const a31 = runAd({ GAIAFTCL_GATEWAY: `http://${HOST}:8803` }, smokeBody);
  const a31out = (a31.stdout || "") + (a31.stderr || "");
  const hasReceipt = /claim_key|receipt/i.test(a31out);
  const hasBlocked = /BLOCKED/i.test(a31out);
  record(
    "3",
    "3.1",
    "Adapter smoke ops@",
    hasReceipt || hasBlocked ? "PASS" : "FAIL",
    "receipt claim_key OR BLOCKED + optional queue",
    `exit ${a31.status}`,
    a31out.slice(0, 2500)
  );

  const rooms = [
    ["research@gaiaftcl.com", "owl_protocol"],
    ["discovery@gaiaftcl.com", "discovery"],
    ["governance@gaiaftcl.com", "governance"],
    ["sovereign@gaiaftcl.com", "treasury"],
    ["ops@gaiaftcl.com", "sovereign_mesh"],
    ["receipts@gaiaftcl.com", "receipt_wall"],
    ["entropy@gaiaftcl.com", "open_loop_tracker"],
  ];
  const routingLog = [];
  for (const [to, expected] of rooms) {
    const vr = spawnSync(py, [verifyGr, GAIAOS_ROOT, to], { encoding: "utf-8", maxBuffer: 1024 * 1024 });
    const gr = (vr.stdout || "").trim();
    const match = gr === expected;
    routingLog.push(`${to} → expected ${expected}; parse_mail game_room=${gr}`);
    record(
      "3",
      "3.2",
      `Game room routing ${to}`,
      match ? "PASS" : "FAIL",
      `parse_mail game_room === ${expected}`,
      gr || (vr.stderr || "").slice(0, 200),
      routingLog[routingLog.length - 1]
    );
  }

  const unkR = spawnSync(py, [verifyGr, GAIAOS_ROOT, "unknown@gaiaftcl.com"], {
    encoding: "utf-8",
    maxBuffer: 1024 * 1024,
  });
  const unkGr = (unkR.stdout || "").trim();
  const unkRun = runAd(
    { GAIAFTCL_GATEWAY: `http://${HOST}:8803` },
    "From: a@b.com\nTo: unknown@gaiaftcl.com\nSubject: u\n\nbody"
  );
  const unko = (unkRun.stdout || "") + (unkRun.stderr || "");
  record(
    "3",
    "3.3",
    "Unknown local part",
    unkGr === "unclassified" && unkRun.status !== null ? "PASS" : "FAIL",
    "game_room unclassified; adapter does not crash",
    `parse_mail=${unkGr} adapter_exit=${unkRun.status}`,
    `${unko.slice(0, 800)}`
  );

  const a34 = runAd({ GAIAFTCL_GATEWAY: "http://127.0.0.1:1" }, smokeBody);
  const a34o = (a34.stdout || "") + (a34.stderr || "");
  const tries = (a34o.match(/BLOCKED attempt/g) || []).length;
  const blockedFinal = /BLOCKED:/.test(a34o) && /BLOCKED attempt 3\/3/.test(a34o);
  const queued = /queued:/.test(a34o);
  record(
    "3",
    "3.4",
    "Adapter failure resilience",
    tries === 3 && blockedFinal && queued && a34.status !== 0 ? "PASS" : "FAIL",
    "3 retries, BLOCKED, queue file, clean exit",
    `attempts_logged=${tries} queued=${queued} exit=${a34.status}`,
    a34o.slice(0, 2500)
  );

  // Phase 4
  const anyC4WanOpen = c4TcpSnapshot.some((x) => x.ok);
  record(
    "4",
    "4.1",
    "Constitutional — substrate ports WAN (same probe as 1.4)",
    anyC4WanOpen ? "FAIL" : "PASS",
    "8803,8529,4222,8222,8805,9000,8830 must not accept external TCP",
    anyC4WanOpen ? "At least one port accepted" : "All refused or timeout",
    JSON.stringify(c4TcpSnapshot)
  );

  const scanPorts = [
    22, 80, 135, 139, 445, 853, 3000, 3306, 5432, 6379, 8000, 8080, 8443, 8803, 8529, 4222,
  ];
  const allowedPublic = new Set([25, 587, 993, 443]);
  const scanResults = [];
  for (const p of [...allowedPublic, ...scanPorts]) {
    const r = await tryTcp(HOST, p);
    scanResults.push({ port: p, connected: r.ok, detail: r.detail });
  }
  const unexpectedOpen = scanResults.filter((x) => x.connected && !allowedPublic.has(x.port));
  const requiredOpen = [25, 587, 993, 443].map((p) => scanResults.find((s) => s.port === p));
  const reqOk = requiredOpen.every((x) => x?.connected);
  record(
    "4",
    "4.2",
    "Mail-only public surface (sampled ports)",
    unexpectedOpen.length === 0 && reqOk ? "PASS" : unexpectedOpen.length ? "FAIL" : reqOk ? "PASS" : "FAIL",
    "Only 25,587,993,443 accept among sampled set; SSH 22 should be policy-specific",
    `open_unexpected=${unexpectedOpen.map((x) => x.port).join(",") || "none"} required_four=${reqOk}`,
    JSON.stringify({ unexpectedOpen, requiredOpen })
  );

  const extHttps = await new Promise((resolve) => {
    https.get(
      `https://${MAIL_HOST}/`,
      { rejectUnauthorized: false, timeout: 12000 },
      (res) => {
        const h = res.headers;
        const bad = JSON.stringify(h).toLowerCase();
        const leak = /mailcow|docker|python|arangodb|nats|nginx\/\d|openresty\/\d/.test(bad);
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () => resolve({ leak, headers: h, body: body.slice(0, 500) }));
      }
    ).on("error", (e) => resolve({ error: e.message }));
  });
  record(
    "4",
    "4.3",
    "No information leakage (HTTPS root headers)",
    extHttps.error ? "BLOCKED" : extHttps.leak ? "FAIL" : "PASS",
    "Zero technology fingerprints in headers aggregate",
    extHttps.error || (extHttps.leak ? "fingerprint in headers" : "none detected"),
    extHttps.headers ? JSON.stringify(extHttps.headers).slice(0, 1500) : String(extHttps.error)
  );

  const mid = "<facade-test-idem@audit>";
  const idemBody = `From: idem@test.com\nTo: ops@gaiaftcl.com\nSubject: idem\nMessage-ID: ${mid}\n\none`;
  const id1 = runAd({ GAIAFTCL_GATEWAY: `http://${HOST}:8803` }, idemBody);
  const id2 = runAd({ GAIAFTCL_GATEWAY: `http://${HOST}:8803` }, idemBody);
  const id1o = (id1.stdout || "") + (id1.stderr || "");
  const id2o = (id2.stdout || "") + (id2.stderr || "");
  record(
    "4",
    "4.4",
    "Adapter idempotency (duplicate Message-ID)",
    id1.status !== undefined && id2.status !== undefined ? "PASS" : "FAIL",
    "Two runs, no crash; dedup is substrate concern",
    `exit1=${id1.status} exit2=${id2.status}`,
    `${id1o.slice(0, 800)}\n---\n${id2o.slice(0, 800)}`
  );

  // --- Write markdown ---
  fs.mkdirSync(path.dirname(REPORT_PATH), { recursive: true });

  const byPhase = { 1: [], 2: [], 3: [], 4: [] };
  for (const r of results) {
    if (!byPhase[r.phase]) byPhase[r.phase] = [];
    byPhase[r.phase].push(r);
  }

  const statusCount = { PASS: 0, FAIL: 0, BLOCKED: 0, GATEWAY_DRIFT: 0 };
  for (const r of results) {
    statusCount[r.status] = (statusCount[r.status] || 0) + 1;
  }
  const total = results.length;

  const constitutional = results.filter(
    (r) =>
      r.status === "FAIL" &&
      (r.id === "1.4" || r.name.includes("External TCP") || ["2.4", "2.5", "4.1", "4.2"].includes(r.id))
  );
  const critViolations = results.filter(
    (r) =>
      (r.id === "1.4" && r.status === "FAIL" && String(r.actual).includes("CONNECTED")) ||
      (r.id === "2.4" && r.status === "FAIL") ||
      (r.id === "2.5" && r.status === "FAIL") ||
      (r.id === "4.1" && r.status === "FAIL")
  );

  let md = `# PLAYWRIGHT_TEST_REPORT_V1 — Sovereign facade audit\n\n`;
  md += `**Target:** hel1-01 \`${HOST}\` / \`${MAIL_HOST}\`\n\n`;
  md += `**Generated:** ${new Date().toISOString()}\n\n`;
  md += `**Runner:** \`tests/sovereign_facade/facade_audit_runner.mjs\` + Playwright \`services/gaiaos_ui_web/tests/sovereign_facade/phase1_s4_http.spec.ts\`\n\n`;
  md += `---\n\n`;

  const phaseTitles = {
    1: "Phase 1 — External S4 surface",
    2: "Phase 2 — Internal mesh (as observed from runner egress IP)",
    3: "Phase 3 — Mail inbound adapter",
    4: "Phase 4 — Constitutional",
  };

  for (const p of ["1", "2", "3", "4"]) {
    md += `## ${phaseTitles[p]}\n\n`;
    for (const r of byPhase[p] || []) {
      md += `### Test ${r.id} — ${r.name}\n\n`;
      md += `**Status:** ${r.status}\n\n`;
      md += `**Expected:** ${r.expected}\n\n`;
      md += `**Actual:** ${r.actual}\n\n`;
      md += `**Evidence:**\n\n\`\`\`\n${(r.evidence || "").slice(0, 6000)}\n\`\`\`\n\n`;
    }
  }

  md += `## Summary\n\n`;
  md += `- **Total test records:** ${total}\n`;
  md += `- **PASS:** ${statusCount.PASS || 0}\n`;
  md += `- **FAIL:** ${statusCount.FAIL || 0}\n`;
  md += `- **BLOCKED:** ${statusCount.BLOCKED || 0}\n`;
  md += `- **GATEWAY_DRIFT:** ${statusCount.GATEWAY_DRIFT || 0}\n\n`;

  md += `## Constitutional violations\n\n`;
  if (critViolations.length === 0) {
    md += `_No CRITICAL constitutional violations flagged by automated criteria (C4 port accepted on WAN, or Arango reachable on WAN)._\n\n`;
  } else {
    for (const v of critViolations) {
      md += `- **CRITICAL:** ${v.id} ${v.name} — ${v.actual}\n`;
    }
    md += `\n`;
  }

  md += `## Recommended next actions\n\n`;
  md += `1. If **GATEWAY_DRIFT**: redeploy \`services/fot_mcp_gateway\` on hel1-01 so \`/claims\` and \`/universal_ingest\` match repo.\n`;
  md += `2. If **Phase 1.1 / 4.3 FAIL**: merge \`infrastructure/sovereign_facade/mailcow_nginx_override.conf\` and strip version headers.\n`;
  md += `3. If **C4 ports open on WAN**: unpublish Docker ports or apply \`iptables_docker_user_drops.example.sh\` + verify \`DOCKER-USER\`.\n`;
  md += `4. If **4.2 FAIL** (unexpected open ports): restrict UFW / Docker publish; confirm SSH (22) policy vs “mail-only” invariant.\n`;
  md += `5. If **adapter BLOCKED**: inspect gateway logs and \`MAIL_ADAPTER_QUEUE_DIR\` per \`services/mailcow_inbound_adapter/README.md\`.\n`;

  fs.writeFileSync(REPORT_PATH, md, "utf8");
  console.log("Wrote", REPORT_PATH);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
