# Witness — sovereign S4 game rooms (Mailcow × C4)

**generated_utc:** (fill, ISO-8601 UTC)  
**operator:**  
**cell / Mailcow host:**  
**primary domain:** gaiaftcl.com  

## Preconditions

- [ ] Mailcow stack running (operator check; optional Mailcow API `GET /api/v1/get/domain/all` on host)
- [ ] MCP Gateway `/health` OK
- [ ] mailcow-bridge reachable from gateway (no 503 on `/mailcow/mailbox`)

## Mailboxes (Step 2)

| Local part   | Game room        | Created (y/n) | Login test (y/n) |
|-------------|------------------|---------------|------------------|
| research    | Owl Protocol     |               |                  |
| governance  | Mother Protocol  |               |                  |
| discovery   | Materials        |               |                  |
| sovereign   | Consortium       |               |                  |
| ops         | Infrastructure   |               |                  |

## Routing (Step 3)

- [ ] Unclassified → ops@
- [ ] Knight allow-list → correct slice (document list location, redact secrets)
- [ ] Unknown sender auto-reply: calories or cures question (y/n / n/a)

## Franklin × MCP (Step 4)

- [ ] research@ hook fires MCP query (y/n / not deployed)
- [ ] discovery@ hook fires MCP query (y/n / not deployed)
- [ ] Claim key appended to metadata on match (y/n / not deployed)

## Test mail (Step 5)

| Slice      | Message-ID / subject | Delivered | Classification correct |
|-----------|----------------------|-----------|-------------------------|
| research  |                      |           |                         |
| governance|                      |           |                         |
| discovery |                      |           |                         |
| sovereign |                      |           |                         |
| ops       |                      |           |                         |

## Terminal statement

- **All five game rooms live:** (yes / no / partial)  
- **BLOCKED events:** (none / list)  
- **Open loops logged to C4:** (claim ids or n/a)  

**Calories or cures. The sovereign mesh carries the meaning.**
