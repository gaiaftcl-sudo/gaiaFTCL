# Mesh graph follow — host port **8812** (head wallet-gate)

Worker cells proxy read-only `GET /graph/*` to the **head** cell’s wallet-gate. They must call a **host port that is not 8803**:

- Each worker publishes **8803** for its **local** wallet-gate.
- Docker installs **OUTPUT DNAT** so outbound TCP with **dport 8803** is redirected to the **local** container; traffic to `http://<head>:8803` never leaves the worker.
- The head therefore exposes the same service on a **second** host port (**8812** → container **8803**). **8804** is not used here because it is already bound by `gaiaftcl-dns-authority` on hel1-01.

Repo wiring:

- `docker-compose.head-graph-follow-port.yml` — merged **only** on **gaiaftcl-hcloud-hel1-01** by `scripts/crystal_remote_deploy.sh`.
- Non-head cells: `MESH_GRAPH_FOLLOW_URL` defaults to `http://77.42.85.60:8812` in that script.

---

## 1. Hetzner `gaiaos-sovereign-firewall` — egress rule

**Purpose:** The sovereign firewall uses a **tight egress allow-list**. Workers must be allowed to open **outbound** TCP to port **8812** (to reach the head’s graph-follow listener).

**Rule (conceptual):** TCP **8812** outbound toward the Internet (IPv4 + IPv6).

**Add via `hcloud`** (outbound rules require **`--destination-ips`**, not `--source-ips`; `--source-ips` is only valid for `--direction in`):

```bash
hcloud firewall add-rule gaiaos-sovereign-firewall \
  --direction out \
  --protocol tcp \
  --port 8812 \
  --destination-ips 0.0.0.0/0,::/0 \
  --description "Mesh wallet-gate graph follow (head 8812)"
```

**Note:** If you only pass `0.0.0.0/0`, IPv6 egress from dual-stack servers may still be blocked for this port; include `::/0` unless you have confirmed IPv6 is unused.

---

## 2. hel1-01 UFW — allow **8812/tcp** from each worker

**Purpose:** On the head, UFW default **routed** policy is **deny**. Docker-published ports need explicit **allow** so WAN → bridge → wallet-gate forwarding works for **8812**.

**Head (current):** `77.42.85.60` (gaiaftcl-hcloud-hel1-01).

**Eight worker IPs** (run on **head** as root):

| Role | IP |
|------|-----|
| gaiaftcl-hcloud-hel1-02 | `135.181.88.134` |
| gaiaftcl-hcloud-hel1-03 | `77.42.32.156` |
| gaiaftcl-hcloud-hel1-04 | `77.42.88.110` |
| gaiaftcl-hcloud-hel1-05 | `37.27.7.9` |
| gaiaftcl-netcup-nbg1-01 | `37.120.187.247` |
| gaiaftcl-netcup-nbg1-02 | `152.53.91.220` |
| gaiaftcl-netcup-nbg1-03 | `152.53.88.141` |
| gaiaftcl-netcup-nbg1-04 | `37.120.187.174` |

**Add via UFW** (one line per IP):

```bash
ufw allow from 135.181.88.134 to any port 8812 proto tcp comment 'mesh graph follow hel1-02'
ufw allow from 77.42.32.156 to any port 8812 proto tcp comment 'mesh graph follow hel1-03'
ufw allow from 77.42.88.110 to any port 8812 proto tcp comment 'mesh graph follow hel1-04'
ufw allow from 37.27.7.9 to any port 8812 proto tcp comment 'mesh graph follow hel1-05'
ufw allow from 37.120.187.247 to any port 8812 proto tcp comment 'mesh graph follow nbg1-01'
ufw allow from 152.53.91.220 to any port 8812 proto tcp comment 'mesh graph follow nbg1-02'
ufw allow from 152.53.88.141 to any port 8812 proto tcp comment 'mesh graph follow nbg1-03'
ufw allow from 37.120.187.174 to any port 8812 proto tcp comment 'mesh graph follow nbg1-04'
ufw reload
```

If **DOCKER-USER** drops non-Docker sources to the published **8812** port (same pattern as 8803), insert **nftables/iptables `RETURN`** rules for these sources on **tcp dport 8812** before the drop (see `iptables_docker_user_drops.example.sh` and chain `DOCKER-USER` on the head).

---

## 3. `docker-compose.head-graph-follow-port.yml`

Already in the repo at `GAIAOS/docker-compose.head-graph-follow-port.yml`.

Used **only** on **hel1-01** by merging in `scripts/crystal_remote_deploy.sh` (`COMPOSE_HEAD=... -f docker-compose.head-graph-follow-port.yml`).

---

## 4. `MESH_GRAPH_FOLLOW_URL=http://77.42.85.60:8812`

Set on **all non-head** cells by default in `scripts/crystal_remote_deploy.sh` when `CELL_ID != gaiaftcl-hcloud-hel1-01`.

Override for tests:

```bash
export MESH_GRAPH_FOLLOW_URL='http://<head-public-ip>:8812'
```

---

## Reproduce from scratch

1. **Bootstrap head (hel1-01)**  
   - Deploy crystal stack so wallet-gate listens on **8803** (in-container) and **8812** (host) via the compose override.  
   - Apply **UFW** (and **DOCKER-USER** if needed) on the head for **8812** from all eight worker IPs.

2. **Hetzner-attached workers**  
   - Ensure `gaiaos-sovereign-firewall` includes the **egress** TCP **8812** rule above (Netcup hosts are not on this firewall unless you attach them).

3. **Workers**  
   - Rsync repo + run `crystal_remote_deploy.sh` with correct `CELL_ID` / `CELL_IP` so `MESH_GRAPH_FOLLOW_URL` points at the head.

### If the head public IP changes

- **Repo / deploy:** Update the default in `scripts/crystal_remote_deploy.sh` (`MESH_GRAPH_FOLLOW_URL`) to `http://<new-head-ip>:8812`, redeploy all **non-head** cells (or set the env in `/etc/gaiaftcl/secrets.env` / compose env consistently).
- **UFW on the new head:** Re-apply the eight `ufw allow from <worker> to any port 8812` rules (and **DOCKER-USER** allows if your drop script covers **8812**).
- **Hetzner firewall:** No change **only** if the rule is still “egress TCP 8812 to 0.0.0.0/0,::/0”. If you ever scope egress by destination CIDR, update that CIDR to the new head IP.

### Quick verification (on any worker)

```bash
curl -sf --connect-timeout 5 --max-time 20 "http://127.0.0.1:8803/graph/stats" | head -c 200
```

Expect HTTP **200** and JSON from the head’s graph projection.
