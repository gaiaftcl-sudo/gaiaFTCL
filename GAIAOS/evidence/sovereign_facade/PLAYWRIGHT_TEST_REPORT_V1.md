# PLAYWRIGHT_TEST_REPORT_V1 — Sovereign facade audit

**Target:** hel1-01 `77.42.85.60` / `mail.gaiaftcl.com`

**Generated:** 2026-03-26T19:31:12.225Z

**Runner:** `tests/sovereign_facade/facade_audit_runner.mjs` + Playwright `services/gaiaos_ui_web/tests/sovereign_facade/phase1_s4_http.spec.ts`

---

## Phase 1 — External S4 surface

### Test 1.1 — Mail server identity hiding

**Status:** PASS

**Expected:** Playwright expectations in phase1_s4_http.spec.ts

**Actual:** passed

**Evidence:**

```

```

### Test 1.2 — Probe path blocking

**Status:** FAIL

**Expected:** Playwright expectations in phase1_s4_http.spec.ts

**Actual:** failed

**Evidence:**

```
Error: /rspamd should be 404

[2mexpect([22m[31mreceived[39m[2m).[22mtoBe[2m([22m[32mexpected[39m[2m) // Object.is equality[22m

Expected: [32m404[39m
Received: [31m301[39m
```

### Test 1.3 — SOGo webmail accessible

**Status:** FAIL

**Expected:** Playwright expectations in phase1_s4_http.spec.ts

**Actual:** failed

**Evidence:**

```
Error: [2mexpect([22m[31mreceived[39m[2m).[22mtoContain[2m([22m[32mexpected[39m[2m) // indexOf[22m

Expected value: [32m404[39m
Received array: [31m[200, 301, 302, 303, 307, 308, 401][39m
```

### Test 1.4 — External TCP 77.42.85.60:8803

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.4 — External TCP 77.42.85.60:8529

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.4 — External TCP 77.42.85.60:4222

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.4 — External TCP 77.42.85.60:8222

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.4 — External TCP 77.42.85.60:8805

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.4 — External TCP 77.42.85.60:9000

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.4 — External TCP 77.42.85.60:8830

**Status:** PASS

**Expected:** Connection refused or timeout; none accept

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

### Test 1.5 — SMTP TCP 25

**Status:** FAIL

**Expected:** Accepts connection; EHLO/banner no internal topology

**Actual:** timeout

**Evidence:**

```
checked
```

### Test 1.5 — SMTP TCP 587

**Status:** PASS

**Expected:** Accepts connection; EHLO/banner no internal topology

**Actual:** 220 backup-mx.gaiaftcl.com ESMTP Postcow\r
250-backup-mx.gaiaftcl.com\r
250-PIPELINING\r
250-SIZE 104857600\r
250-ETRN\r
250-STARTTLS\r
250-ENHANCEDSTATUSCODES\r
250-8BITMIME\r
250 DSN\r
250-backup-mx.gaiaftcl.com\r
250-PIPELINING\r
250-SIZE 104857600\r
250-ETRN\r
250-STARTTLS\r
250-ENHANCEDSTATUSCODES\r
250-8BITMIME\r
250 DSN\r
250-backup-mx.gaiaftcl.com\r
250-PIPELINING\r
250-SIZE 104857600\r
25

**Evidence:**

```
checked
```

### Test 1.6 — IMAPS 993

**Status:** FAIL

**Expected:** Accepts; banner no version/internal details

**Actual:** timeout

**Evidence:**

```
checked
```

## Phase 2 — Internal mesh (as observed from runner egress IP)

### Test 2.1 — Gateway health

**Status:** BLOCKED

**Expected:** 200 healthy, NATS connected

**Actual:** status timeout

**Evidence:**

```
timeout
```

### Test 2.2 — Claims endpoint

**Status:** BLOCKED

**Expected:** 200 JSON array with claim documents

**Actual:** timeout

**Evidence:**

```

```

### Test 2.3 — Universal ingest

**Status:** BLOCKED

**Expected:** 200/201 with claim key

**Actual:** timeout

**Evidence:**

```

```

### Test 2.4 — Arango external

**Status:** PASS

**Expected:** Must not be reachable externally (no TCP/HTTP to 8529 from WAN)

**Actual:** timeout

**Evidence:**

```

```

### Test 2.5 — NATS 4222 external

**Status:** PASS

**Expected:** Refused or timeout

**Actual:** timeout

**Evidence:**

```
{"ok":false,"detail":"timeout"}
```

## Phase 3 — Mail inbound adapter

### Test 3.1 — Adapter smoke ops@

**Status:** PASS

**Expected:** receipt claim_key OR BLOCKED + optional queue

**Actual:** exit 1

**Evidence:**

```
BLOCKED attempt 1/3: URLError: timed out
BLOCKED attempt 2/3: URLError: timed out
BLOCKED attempt 3/3: URLError: timed out
BLOCKED: URLError: timed out
queued: /tmp/gaiaftcl-mail-inbound-queue/1774552932545_1774552932545867000.json

```

### Test 3.2 — Game room routing research@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === owl_protocol

**Actual:** owl_protocol

**Evidence:**

```
research@gaiaftcl.com → expected owl_protocol; parse_mail game_room=owl_protocol
```

### Test 3.2 — Game room routing discovery@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === discovery

**Actual:** discovery

**Evidence:**

```
discovery@gaiaftcl.com → expected discovery; parse_mail game_room=discovery
```

### Test 3.2 — Game room routing governance@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === governance

**Actual:** governance

**Evidence:**

```
governance@gaiaftcl.com → expected governance; parse_mail game_room=governance
```

### Test 3.2 — Game room routing sovereign@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === treasury

**Actual:** treasury

**Evidence:**

```
sovereign@gaiaftcl.com → expected treasury; parse_mail game_room=treasury
```

### Test 3.2 — Game room routing ops@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === sovereign_mesh

**Actual:** sovereign_mesh

**Evidence:**

```
ops@gaiaftcl.com → expected sovereign_mesh; parse_mail game_room=sovereign_mesh
```

### Test 3.2 — Game room routing receipts@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === receipt_wall

**Actual:** receipt_wall

**Evidence:**

```
receipts@gaiaftcl.com → expected receipt_wall; parse_mail game_room=receipt_wall
```

### Test 3.2 — Game room routing entropy@gaiaftcl.com

**Status:** PASS

**Expected:** parse_mail game_room === open_loop_tracker

**Actual:** open_loop_tracker

**Evidence:**

```
entropy@gaiaftcl.com → expected open_loop_tracker; parse_mail game_room=open_loop_tracker
```

### Test 3.3 — Unknown local part

**Status:** PASS

**Expected:** game_room unclassified; adapter does not crash

**Actual:** parse_mail=unclassified adapter_exit=1

**Evidence:**

```
BLOCKED attempt 1/3: URLError: timed out
BLOCKED attempt 2/3: URLError: timed out
BLOCKED attempt 3/3: URLError: timed out
BLOCKED: URLError: timed out
queued: /tmp/gaiaftcl-mail-inbound-queue/1774553071281_1774553071281406000.json

```

### Test 3.4 — Adapter failure resilience

**Status:** PASS

**Expected:** 3 retries, BLOCKED, queue file, clean exit

**Actual:** attempts_logged=3 queued=true exit=1

**Evidence:**

```
BLOCKED attempt 1/3: URLError: [Errno 61] Connection refused
BLOCKED attempt 2/3: URLError: [Errno 61] Connection refused
BLOCKED attempt 3/3: URLError: [Errno 61] Connection refused
BLOCKED: URLError: [Errno 61] Connection refused
queued: /tmp/gaiaftcl-mail-inbound-queue/1774553074388_1774553074388011000.json

```

## Phase 4 — Constitutional

### Test 4.1 — Constitutional — substrate ports WAN (same probe as 1.4)

**Status:** PASS

**Expected:** 8803,8529,4222,8222,8805,9000,8830 must not accept external TCP

**Actual:** All refused or timeout

**Evidence:**

```
[{"port":8803,"ok":false,"detail":"timeout"},{"port":8529,"ok":false,"detail":"timeout"},{"port":4222,"ok":false,"detail":"timeout"},{"port":8222,"ok":false,"detail":"timeout"},{"port":8805,"ok":false,"detail":"timeout"},{"port":9000,"ok":false,"detail":"timeout"},{"port":8830,"ok":false,"detail":"timeout"}]
```

### Test 4.2 — Mail-only public surface (sampled ports)

**Status:** FAIL

**Expected:** Only 25,587,993,443 accept among sampled set; SSH 22 should be policy-specific

**Actual:** open_unexpected=22,80,8080 required_four=false

**Evidence:**

```
{"unexpectedOpen":[{"port":22,"connected":true,"detail":"connected"},{"port":80,"connected":true,"detail":"connected"},{"port":8080,"connected":true,"detail":"connected"}],"requiredOpen":[{"port":25,"connected":false,"detail":"timeout"},{"port":587,"connected":true,"detail":"connected"},{"port":993,"connected":false,"detail":"timeout"},{"port":443,"connected":true,"detail":"connected"}]}
```

### Test 4.3 — No information leakage (HTTPS root headers)

**Status:** PASS

**Expected:** Zero technology fingerprints in headers aggregate

**Actual:** none detected

**Evidence:**

```
{"server":"nginx","date":"Thu, 26 Mar 2026 19:26:35 GMT","content-type":"text/html; charset=utf-8","transfer-encoding":"chunked","connection":"keep-alive","vary":"Accept-Encoding","set-cookie":["MCSESSID=d5419c0d6955a760f514f56ef0629d61; path=/; secure; HttpOnly; SameSite=Lax"],"expires":"Thu, 19 Nov 1981 08:52:00 GMT","cache-control":"no-store, no-cache, must-revalidate","pragma":"no-cache","strict-transport-security":"max-age=15768000;","x-content-type-options":"nosniff","x-robots-tag":"none","x-download-options":"noopen","x-frame-options":"SAMEORIGIN","x-permitted-cross-domain-policies":"none","referrer-policy":"strict-origin"}
```

### Test 4.4 — Adapter idempotency (duplicate Message-ID)

**Status:** PASS

**Expected:** Two runs, no crash; dedup is substrate concern

**Actual:** exit1=1 exit2=1

**Evidence:**

```
BLOCKED attempt 1/3: URLError: timed out
BLOCKED attempt 2/3: URLError: timed out
BLOCKED attempt 3/3: URLError: timed out
BLOCKED: URLError: timed out
queued: /tmp/gaiaftcl-mail-inbound-queue/1774553334092_1774553334092690000.json

---
BLOCKED attempt 1/3: URLError: timed out
BLOCKED attempt 2/3: URLError: timed out
BLOCKED attempt 3/3: URLError: timed out
BLOCKED: URLError: timed out
queued: /tmp/gaiaftcl-mail-inbound-queue/1774553472211_1774553472211359000.json

```

## Summary

- **Total test records:** 32
- **PASS:** 24
- **FAIL:** 5
- **BLOCKED:** 3
- **GATEWAY_DRIFT:** 0

## Constitutional violations

_No CRITICAL constitutional violations flagged by automated criteria (C4 port accepted on WAN, or Arango reachable on WAN)._

## Recommended next actions

1. If **GATEWAY_DRIFT**: redeploy `services/fot_mcp_gateway` on hel1-01 so `/claims` and `/universal_ingest` match repo.
2. If **Phase 1.1 / 4.3 FAIL**: merge `infrastructure/sovereign_facade/mailcow_nginx_override.conf` and strip version headers.
3. If **C4 ports open on WAN**: unpublish Docker ports or apply `iptables_docker_user_drops.example.sh` + verify `DOCKER-USER`.
4. If **4.2 FAIL** (unexpected open ports): restrict UFW / Docker publish; confirm SSH (22) policy vs “mail-only” invariant.
5. If **adapter BLOCKED**: inspect gateway logs and `MAIL_ADAPTER_QUEUE_DIR` per `services/mailcow_inbound_adapter/README.md`.
