# Recovery — hel1-01 SSH after UFW (2026-03-26)

## What happened

1. **DOCKER-USER drops** were applied successfully (insert-before-RETURN rules). External TCP to **8803 / 8529 / 4222** from the audit runner **timed out** (no connect) — Step 1 objective met.

2. **UFW** was enabled with an SSH allow rule that matched **`203.0.113.10`** (documentation TEST-NET-3 placeholder) instead of the operator’s real source IP. The live admin path from the automation egress was **`73.126.136.66`**, so **new SSH sessions to `77.42.85.60:22` may time out** (default deny + wrong allow).

3. **UWP package** was installed on the host during this session (`ufw` was not present before).

## Immediate recovery (Hetzner / Netcup console or rescue)

Log in via **out-of-band console** (not SSH), then:

```bash
# See rules
ufw status numbered

# Remove the bad SSH rule (use the number from "status numbered" for 203.0.113.10)
ufw delete <N>

# Allow your real admin IPv4 (replace with your current public IP /32 or office CIDR)
ufw allow from YOUR.PUBLIC.IP.HERE/32 to any port 22 proto tcp comment 'gaiaftcl ssh admin'

ufw reload
ufw status verbose
```

If you use **IPv6** for SSH, add a matching `ufw allow .../128` or the appropriate v6 rule.

## After SSH works again

1. Copy the **fixed** `iptables_docker_user_drops.example.sh` (uses **`iptables -I DOCKER-USER 1`**, not `-A`, so rules run before Docker’s blanket `RETURN`).

2. Install persistence:

```bash
sudo install -m 755 /path/to/iptables_docker_user_drops.example.sh /usr/local/bin/gaiaftcl-docker-user-drops.sh
sudo install -m 644 /path/to/gaiaftcl-docker-user-iptables.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gaiaftcl-docker-user-iptables.service
```

3. Re-apply UFW **only** with explicit admin IP:

```bash
export ADMIN_SSH_SOURCES='YOUR.PUBLIC.IP/32'
bash infrastructure/sovereign_facade/ufw_rules.sh
# Script now refuses empty or 203.0.113.* placeholders
sudo ufw --force enable
```

4. Re-run: `node tests/sovereign_facade/facade_audit_runner.mjs`

## Repo fixes applied (this commit path)

- **`iptables_docker_user_drops.example.sh`**: `-A` → **`-I DOCKER-USER 1`** so drops are effective when `RETURN` is the only prior rule.
- **`ufw_rules.sh`**: **exits with FATAL** if `ADMIN_SSH_SOURCES` is unset or contains **`203.0.113`**.
- **`gaiaftcl-docker-user-iptables.service`**: example **systemd** unit for post-`docker.service` re-apply.
