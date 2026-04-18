# Fusion sidecar — guest bootstrap (Linux VM)

Embed or copy these into your **Ubuntu arm64 cloud** guest image (cloud-init, Ansible, or golden image). The **Mac app** can expose the host GAIAOS checkout read-only via **virtiofs** tag **`gaiaos`** → mount at **`/opt/gaiaos`**.

**Field of fields (parallel vs blocked):** [`../../evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md`](../../evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md)

---

## 1. virtiofs mount (guest)

After boot (and after `virtiofs` kernel module loads):

```bash
sudo mkdir -p /opt/gaiaos
sudo mount -t virtiofs gaiaos /opt/gaiaos
```

Persist in **`/etc/fstab`**:

```fstab
gaiaos /opt/gaiaos virtiofs ro,relatime 0 0
```

(`ro` matches read-only share from **FusionSidecarHost**.)

---

## 2. Bring up the C⁴ stack

From the mounted tree (compose at repo root):

```bash
cd /opt/gaiaos
docker compose -f docker-compose.fusion-sidecar.yml up -d --build
```

---

## 3. systemd (optional)

Install [`fusion-sidecar-compose.service`](fusion-sidecar-compose.service) to **`/etc/systemd/system/`**, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now fusion-sidecar-compose.service
```

Requires **Docker Engine** and **docker compose** plugin in the guest.

---

## 4. cloud-init snippets

- [`network-config-static.yaml`](network-config-static.yaml) — static **`192.168.64.10/24`** (aligns with app default **Guest IPv4**).
- [`user-data.fragment.yaml`](user-data.fragment.yaml) — merge into full `user-data` (install docker, fstab, systemd).

---

## 5. Mac app

In **FusionSidecarHost**, choose **GAIAOS root (virtiofs)** so the VM gets tag **`gaiaos`**. Without it, copy the repo into the guest disk or bind-mount another way.

*Norwich / GaiaFTCL.*
