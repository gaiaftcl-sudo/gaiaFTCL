# Witness — Sovereign S4 facade artifacts

**Scope:** Repository specification for zero–attack-surface mail boundary (S4) vs internal C4 stack. **Not** a live production apply receipt.

## Inventory (`infrastructure/sovereign_facade/`)

| Artifact | Role |
|----------|------|
| `README.md` | Architecture, UFW/Docker gotchas, merge guidance |
| `mailcow_nginx_override.conf` | HTTPS header discipline + denylist paths |
| `postfix_transport_maps.conf` | Seven game-room transports → `gaiaftcl-mail` |
| `postfix_master_cf_pipe.conf` | Postfix `master.cf` pipe → `adapter.py` |
| `ufw_rules.sh` | Host inbound allowlist (mail + HTTPS + scoped SSH) |
| **`iptables_docker_user_drops.example.sh`** | **`DOCKER-USER`** drops for **8803, 8529, 4222, 8222, 8805, 9000, 8830** from sources outside **`DOCKER_INTERNAL_CIDR`** (default `172.16.0.0/12`); **WARNED** header covers Docker iptables churn and persistence (`rc.local` / **systemd after docker.service**) |

## Apply / verify (reference)

- **iptables example:** `sudo bash infrastructure/sovereign_facade/iptables_docker_user_drops.example.sh`
- **Verify chain:** `sudo iptables -L DOCKER-USER -n -v`

## Automated facade audit (hel1-01)

| Artifact | Role |
|----------|------|
| `tests/sovereign_facade/facade_audit_runner.mjs` | Orchestrator: Playwright Phase 1, TCP/HTTP probes, adapter phases, markdown report |
| `tests/sovereign_facade/verify_game_room.py` | Imports adapter `parse_mail` to assert seven game rooms + `unclassified` |
| `services/gaiaos_ui_web/tests/sovereign_facade/phase1_s4_http.spec.ts` | Playwright HTTP/HTTPS S4 checks (`mail.gaiaftcl.com`) |
| `services/gaiaos_ui_web/tests/sovereign_facade/playwright.sovereign.config.ts` | Isolated Playwright config (avoids `GAIAOS/node_modules` shadowing) |
| **`evidence/sovereign_facade/PLAYWRIGHT_TEST_REPORT_V1.md`** | **Structured witness** from the latest run (`node tests/sovereign_facade/facade_audit_runner.mjs`) |

Run:

```bash
cd GAIAOS && node tests/sovereign_facade/facade_audit_runner.mjs
```

## Related

- `services/mailcow_inbound_adapter/README.md`
- `docs/SUBSTRATE_COMMS_ORGAN.md`
