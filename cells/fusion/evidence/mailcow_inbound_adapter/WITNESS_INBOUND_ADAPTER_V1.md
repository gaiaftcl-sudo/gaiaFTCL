# Witness — Mailcow inbound adapter v1 (build only, no Postfix wire)

**generated_utc:** 2026-03-25 (session)  
**status:** Code + docs in repo. **Postfix / Mailcow not modified** on any host.

## Files created

| Path | Role |
|------|------|
| `services/mailcow_inbound_adapter/adapter.py` | Read RFC822 (stdin or path), parse MIME (`From`, `To`, `Subject`, plain body, `Message-ID`, `Date` → ISO8601, `Reply-To`), map **To:** local-part → `game_room`, `POST {GAIAFTCL_GATEWAY}/universal_ingest`, **≤3** retries, stderr logging, `BLOCKED` + queue on failure |
| `services/mailcow_inbound_adapter/queue.py` | `enqueue_failure()` — JSON files under `MAIL_ADAPTER_QUEUE_DIR` (default `/tmp/gaiaftcl-mail-inbound-queue`) |
| `services/mailcow_inbound_adapter/README.md` | Env vars, game-room table, **reference** `master.cf` / `main.cf` / Sieve notes (explicit: Sieve pipe often disabled; prefer Postfix `transport_maps`) |

## Behavior summary

- **Does:** MIME parse, game-room routing table, structured **`MAIL`** body for `universal_ingest` (`type`, `from`, `payload` with `caller_id`, `status: unresolved`, etc.).
- **Does not:** LLM, `/ask`, Franklin narrative, Mailcow HTTP API, DB, inbound mail modification, automatic queue drain.

## Import note

`adapter.py` loads sibling `queue.py` via `importlib` so Python’s stdlib **`queue`** module is never shadowed.

## Operator verification (after deploy)

```bash
cd cells/fusion/services/mailcow_inbound_adapter
printf '%s\n' 'From: a@b.com
To: research@gaiaftcl.com
Subject: test
Message-ID: <t1@local>
Date: Mon, 1 Jan 2024 12:00:00 +0000

hello' | GAIAFTCL_GATEWAY=http://127.0.0.1:8803 python3 adapter.py
```

Expect stderr `receipt claim_key=...` on success.

## Next step (out of scope for this witness)

Apply Postfix `master.cf` + `transport_maps` on the Mailcow host per README; add TLS/auth policy for gateway if exposed.

**Foundation first. The mouth is built; the jaw waits for ops.**
