# GitGame — Local Repo Automation for the Dev Cell

**Goal:** remove git friction from agents by routing every git / GitHub
operation through a named, schema‑validated, receipt‑producing "game"
handled by a local daemon on the dev cell. Agents never touch git
directly; the operator still owns the `main` gate.

**One‑sentence summary:** put a systemd service inside the existing
Debian mesh‑cell VM, give it its own clone of the repo and its own SSH
key, expose a small localhost RPC, define every GitHub‑touching
operation as a named game with a strict JSON schema, emit a signed
receipt for every attempted game (success **or** refusal).

---

## 0. Why this exists

Recent evidence of the friction, from the last few hours:

- Agent shell cannot remove a stale `.git/index.lock` on the virtiofs
  mount (`Operation not permitted`), which blocks any commit.
- `git add` / `git rm` / `git mv` / `git commit` / `git push` are all
  operator‑only per `.cursorrules` KERNEL DEADLOCK PROTOCOL (AppKit /
  VFS / Aqua‑session boundary), so the agent has to hand‑off a
  copy‑paste block and hope the operator runs it correctly.
- When a coding agent writes a file and the operator isn't at the
  keyboard, the change sits in the working tree until someone notices.
  This is how drift accumulates.
- The newly‑landed `receipt-hygiene.yml` and `sparkle-release-lint.yml`
  gates depend on PRs being opened properly; there is no local
  enforcement layer that refuses a malformed PR before it leaves the
  machine.

GitGame is the explicit, auditable escape hatch. Every git operation
becomes a game; every game has a schema; every invocation produces a
receipt that chains into the `fot-*` namespace.

---

## 1. Constraints the design has to respect

The Mac dev cell is **not** a generic Linux host. The following
constraints are non‑negotiable:

- **Operator qualification boundary.** `main` lands only when an
  operator co‑signs under the Aqua session. GitGame can prepare,
  validate, and stage — it cannot self‑certify operator OQ / PQ.
- **Receipt envelope.** Every landed change must chain into the
  existing `fot-*` signed‑receipt namespace with `parent_hash`.
  M‑provenance receipts need a `receipt_sig`; the
  `receipt-hygiene.yml` gate already enforces this.
- **No M→main without operator signature.** Software‑only signatures
  land as `M_SIL`; physical / operator‑witnessed receipts land as `M`
  with an Ed25519 signature over the canonical JSON.
- **Sparkle release integrity.** `SUPublicEDKey` / `SUFeedURL`
  placeholders in `GAIAOS/macos/GaiaFTCLConsole/project.yml` must
  never reach a Release build. The existing zsh lint is authoritative
  and GitGame calls it before any release‑affecting game.
- **Nine‑cell sovereign substrate.** GitGame is a sidecar to the Mac
  cell; it is not itself a substrate cell. It must not claim
  qualification authority.

---

## 2. Where it runs — Debian mesh‑cell VM, yes

Recommended target: the existing Debian VM that already runs the
local mesh cell. Rationale:

- Isolated execution context (no interference with the operator's Aqua
  session or Keychain).
- Reproducible (systemd unit, package pins, dedicated service user).
- Already on the dev cell's virtio bridge, so localhost RPC from the
  Mac side is a single hop.
- The VM can hold its own Ed25519 deploy key without tangling with the
  operator's personal SSH agent.

Rejected alternative: native macOS `launchd` service. It would run
inside the user session, entangle with Keychain, and blur the
operator‑qualification boundary. Don't.

Sketch:

```
┌──────────────────────────────────────────────────────────────┐
│  Mac (operator's Aqua session)                               │
│  ┌──────────────────────────┐    ┌────────────────────────┐  │
│  │ Operator's working clone │    │ Agents (Cowork, Cursor, │  │
│  │ /Users/.../FoT8D         │    │ Claude Code, etc.)      │  │
│  └─────────────┬────────────┘    └────────┬───────────────┘  │
│                │ git push/pull (operator)   │ localhost RPC   │
│                ▼                             ▼                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Debian mesh‑cell VM (virtiofs + virtio‑net)              │ │
│  │                                                          │ │
│  │  ┌─────────────────┐   ┌────────────────────────────┐    │ │
│  │  │ GitGame daemon  │◀──│ localhost HTTP :7531 (mTLS) │   │ │
│  │  │ (systemd svc)   │   └────────────────────────────┘    │ │
│  │  │                 │                                      │ │
│  │  │  ◀── agent games: propose / ship / retire / …         │ │
│  │  │                                                        │ │
│  │  │  ┌──────────────┐   ┌───────────────┐                  │ │
│  │  │  │ Game clone   │──▶│ Ed25519 deploy │── git push ───▶ │ │
│  │  │  │ /srv/gitgame/│   │ key (VM only) │                  │ │
│  │  │  │ FoT8D.git    │   └───────────────┘                  │ │
│  │  │  └──────────────┘                                      │ │
│  │  │         │                                              │ │
│  │  │         ├─ writes receipts → evidence/gitgame/         │ │
│  │  │         └─ posts to GitHub API (gh cli)                │ │
│  │  └────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                         github.com/<repo>
                         (branch protection on main)
```

---

## 3. The Game catalog — every GitHub‑touching operation, defined

A game is a named operation with a JSON request schema, a set of
preconditions, an exact side‑effect, and a receipt shape. No agent
operation on GitHub is allowed outside this catalog. If an operation
is missing from the catalog, add it to the catalog first, then run it.

Games are grouped into three tiers. Build tier 1 first.

### Tier 1 — core (build first)

`status` — read‑only diagnostic. Returns current branch, ahead/behind
counts vs `origin/main`, uncommitted file count, and whether any
workflow run is in progress. No side effects. Always safe.

`propose` — create a branch, apply a patch, open a PR.
Inputs: `branch_name`, `base_branch` (default `main`), `commit_message`,
`patch` (unified diff) or `file_changes` (list of path+contents),
`pr_title`, `pr_body`, `labels[]`, `reviewers[]`. Preconditions:
`branch_name` does not exist on remote; patch applies cleanly;
`pr_body` is non‑empty; patch touches no file on the restricted list
(see §7). Side effects: create branch, commit, push, open PR. Receipt:
`M_SIL`, chained to parent commit.

`receipt-land` — commit a receipt JSON under `evidence/**`.
Inputs: `target_path` (must match `evidence/**` or
`GAIAOS/**/evidence/**`), `receipt_json`, `provenance_tag` (`M_SIL` or
`M`), `receipt_sig` (required if `M`), `parent_hash`. Preconditions:
receipt‑hygiene rules pass locally (same Python walker as the CI
workflow); `provenance_tag: M` requires a valid Ed25519 signature that
verifies against a registered operator pubkey. Side effects: branch +
commit + PR (never direct to main). Receipt: `M_SIL`.

`retire-file` — `git rm` a file.
Inputs: `path`, `reason`, `replacement_path` (optional, for "moved to").
Preconditions: path is not on the protected list (`.github/`, `main`
workflow files, `.cursorrules`, signing‑key files); `reason` references
either a PR, an issue, or a review receipt. Side effects: branch +
`git rm` + PR. Operator merges.

`rename-file` — `git mv`.
Inputs: `old_path`, `new_path`, `reason`. Preconditions: same
protected‑list check; `new_path` doesn't exist; parent directory of
`new_path` exists or will be created. Side effects: branch + `git mv`
+ PR.

`ship` — merge a PR to `main`. **Operator‑only.**
Inputs: `pr_number`, `merge_method` (`rebase`, `squash`, or
`fast-forward`; default `fast-forward`), `operator_sig` (Ed25519 over
the PR head SHA + target branch + method). Preconditions: all required
CI checks green; PR approved; operator signature verifies against a
registered operator pubkey. Side effects: merge via GitHub API, delete
source branch. Receipt: `M` (operator‑witnessed), chained from the PR
head receipt.

`sync` — fetch + rebase GitGame's clone against `origin/main`.
Inputs: none. Preconditions: no in‑flight games. Side effects:
internal state only, no remote changes. Runs on a timer (every 60 s)
and on demand.

`refuse` — record a rejected game as evidence of the refusal.
Not normally called directly; every failed game produces a `refuse`
receipt automatically. Schema: `{game, args_hash, refusal_reason,
timestamp, parent_hash, sig}`.

### Tier 2 — useful soon (build second)

`tag` — create a lightweight or annotated tag. Inputs: `name`,
`message`, `target_ref`. Annotated tags require `operator_sig`.

`release` — create a GitHub Release from a tag. Inputs: `tag_name`,
`title`, `notes`, `artifacts[]` (paths in the clone). Sparkle‑affected
releases fail unless `sparkle-release-lint` passed in the last N
minutes.

`workflow-dispatch` — trigger a `workflow_dispatch`‑enabled workflow.
Inputs: `workflow_file`, `ref`, `inputs{}`. Rate‑limited.

`workflow-status` — read a workflow run status. Inputs: `run_id` or
`workflow_file+head_sha`. Read‑only.

`artifact-fetch` — download a workflow run artifact into the VM.
Inputs: `run_id`, `artifact_name`. Landing the artifact in the repo
requires a separate `receipt-land` game.

`comment` — comment on a PR or issue. Inputs: `pr_or_issue_number`,
`body`. Rate‑limited to N per hour per thread.

`label` — add / remove labels. Inputs: `pr_or_issue_number`,
`add[]`, `remove[]`.

`close-issue` — close an issue with a reason. Inputs: `issue_number`,
`reason`, `state_reason` (`completed` or `not_planned`).

### Tier 3 — advanced (build if needed)

`cherry-pick` — cherry‑pick a commit onto a branch. Inputs:
`commit_sha`, `target_branch`, `new_branch_name`.

`revert` — revert a commit on a branch. Inputs: `commit_sha`,
`target_branch`, `new_branch_name`, `reason`.

`mirror-push` — push a ref to a second remote (e.g.
`gaiaftcl` remote). Inputs: `remote_name`, `local_ref`, `remote_ref`.

`hotfix` — emergency branch from `main` with reduced gates.
Requires fresh operator co‑signature (not cached). Records a
`hotfix_invoked` receipt regardless of outcome.

`rollback-main` — revert the last N commits on `main` to a known
good SHA. **Operator‑only, always requires fresh co‑signature,
always opens a PR rather than force‑pushing.**

Explicitly **not** games: force push to `main`, direct commits to
`main`, disabling branch protection, rotating GitGame's own deploy
key. These require operator ritual outside GitGame entirely.

---

## 4. Request / response protocol

Localhost HTTP on the VM's virtio‑net bridge, mTLS, JSON bodies.
Minimal HTTP surface:

- `POST /games/<game>` — invoke a game. Body is the game's request
  schema. Response is the receipt JSON. Errors return a `refuse`
  receipt.
- `GET /games/<game>/schema` — fetch the JSON schema for a game.
- `GET /games` — list available games (with tier and short description).
- `GET /receipts/<receipt_id>` — fetch a historical receipt.
- `GET /healthz` — liveness + version + daemon uptime.

Agents authenticate with client certificates pinned in the VM's
`ca-bundle`. Each agent has its own cert (one per Cowork session,
one per Cursor, one per Claude Code, etc.). The cert CN becomes part
of the receipt's `invoked_by` field so refusal audits can pinpoint
the caller.

Every response carries `receipt_id`, `game`, `status`
(`ACCEPTED` / `REJECTED` / `COMPLETED`), `parent_hash`, `sha`
(if the game produced a commit), and `sig` (Ed25519 over canonical
JSON by GitGame's own signing key — **not** the operator's).

---

## 5. Receipt schema (GitGame‑specific)

Every game writes a receipt to
`evidence/gitgame/<YYYY>/<MM>/<DD>/<receipt_id>.json`. The receipt is
committed as part of the game's branch / PR, so receipt‑hygiene in CI
picks it up.

```json
{
  "receipt_id": "gitgame-2026-04-18-1717-XXXXXX",
  "game": "propose",
  "schema_version": "1.0",
  "invoked_by": "cowork-session-<uuid>",
  "args_hash": "sha256:…",
  "target": { "branch": "agent/propose-xyz", "base": "main" },
  "preconditions": { "patch_applies": true, "protected_list_ok": true },
  "side_effects": [
    { "op": "git_commit", "sha": "<sha>" },
    { "op": "git_push",   "ref": "refs/heads/agent/propose-xyz" },
    { "op": "pr_open",    "number": 1234, "url": "…" }
  ],
  "provenance_tag": "M_SIL",
  "parent_hash": "sha256:<previous receipt id>",
  "timestamp": "2026-04-18T17:17:00Z",
  "status": "COMPLETED",
  "sig": "<Ed25519 by GitGame key>",
  "operator_sig": null,
  "notes": "…"
}
```

- `M_SIL` by default. `M` only for `ship`, `tag` (annotated),
  `release`, `hotfix`, `rollback-main`, and any `receipt-land` game
  that explicitly requests `M` **and** supplies a valid
  `operator_sig`.
- The `receipt-hygiene.yml` workflow will already refuse `M` receipts
  without `receipt_sig` / `operator_sig`, so the CI gate enforces the
  same rule the daemon enforces locally. Belt + suspenders.

---

## 6. Key management

Three distinct key pairs, on three distinct machines:

| Key | Lives on | Signs what | Rotates |
| --- | --- | --- | --- |
| Operator Ed25519 | Mac Keychain, Aqua session | `ship`, `release`, `hotfix`, M‑provenance receipts | On operator ritual, tracked in `.cursorrules` |
| GitGame daemon Ed25519 | Debian VM, `/srv/gitgame/keys/`, 0600 | Every receipt it emits, every git commit it authors | On VM rebuild or on incident |
| GitGame GitHub deploy key | Debian VM, registered as a GitHub Deploy Key for this repo | `git push` to feature branches (never `main`) | Same as above |

Branch protection on `main`:
- require PR,
- require GitGame's `receipt-hygiene` workflow green,
- require `mac-cell-ci` green (or equivalent Swift path),
- require `sparkle-release-lint` green when Sparkle files changed,
- require at least one operator approval,
- restrict who can push directly → only the operator's human account
  (not the deploy key; the deploy key pushes feature branches only).

The daemon's deploy key explicitly cannot push to `main`. So even a
compromised GitGame daemon cannot land a bad commit on `main`; it can
only open a PR that the operator then has to merge.

---

## 7. Protected‑list (files GitGame will refuse to touch without operator)

Any attempt to `propose` / `retire-file` / `rename-file` against these
paths returns a `refuse` receipt unless the request carries a fresh
`operator_sig`:

- `.github/**` (repo metadata; **no** Actions workflows live here anymore — still protect from naive edits)
- `.cursorrules`
- `.cursorrules_IQOQPQ`
- `.signing_keys/*`
- `.ssh_keys/*`
- `GAIAOS/macos/GaiaFTCLConsole/project.yml` (Sparkle)
- `GAIAOS/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh`
- `Cargo.toml` (root), `Cargo.lock`
- `evidence/**` with `provenance_tag: M` (must go through
  `receipt-land` with explicit `operator_sig`)
- `fot-*` namespace files

---

## 8. Phased implementation plan

**Phase 0 — preconditions (operator, one‑time).**
Register the GitGame deploy key on GitHub. Add branch protection on
`main`. Publish the GitGame daemon's signing pubkey in
`.cursorrules` so receipts can be audited offline.

**Phase 1 — MVP.** Build the daemon, the RPC surface, and the Tier 1
games (`status`, `propose`, `receipt-land`, `sync`, `refuse`, `ship`).
`ship` is operator‑only; everything else is agent‑callable. Agents
authenticate with one shared client cert for now.

**Phase 2 — full Tier 1.** Add `retire-file`, `rename-file`. Tighten
the protected list. Write a short operator runbook.

**Phase 3 — Tier 2.** Add `tag`, `release`, `workflow-dispatch`,
`workflow-status`, `artifact-fetch`, `comment`, `label`,
`close-issue`. Introduce per‑agent client certificates.

**Phase 4 — Tier 3 and hardening.** Rate limits per agent, per game,
per target branch. Structured refusal audit. Dashboard at
`https://gitgame.local/` showing recent games, receipts, refusals.
Optional: tie GitGame status into the MacHealth / GaiaFusion OQ
dashboards.

**Phase 5 — retire the copy‑paste handoff.** Update `.cursorrules` to
make the GitGame RPC the canonical agent git interface, and strip
`git add/commit/push/rm/mv` from any agent‑visible instruction.

---

## 9. Debian VM specifics

Minimum viable deployment:

- Ubuntu 24.04 LTS or Debian 12 guest inside the existing macOS
  virtualization stack (`vz` framework, UTM, or equivalent — use what
  the mesh cell already runs).
- systemd service: `gitgame.service` owned by `gitgame:gitgame`
  (non‑root service user). `ProtectSystem=strict`,
  `PrivateTmp=yes`, `NoNewPrivileges=yes`, `ReadWritePaths` limited
  to `/srv/gitgame/`.
- Clone at `/srv/gitgame/FoT8D.git` (bare‑ish; the daemon manages
  worktrees under `/srv/gitgame/worktrees/<game-id>/` so parallel
  games don't step on each other).
- `gh` CLI for GitHub API calls; auth via the deploy key + a
  fine‑scope GitHub App installation token if PR opening needs more
  than the deploy key can do.
- Python 3.12 or Rust — pick whichever is easier to audit. The CI
  already has both. Rust is preferred for the signing surface.
- Prometheus metrics on `:9101` for `games_total`, `refusals_total`,
  `push_failures_total`, `receipt_chain_lag_seconds`.
- Log rotation + structured logs to `journalctl`; daily rotation of a
  human‑readable audit log under `/var/log/gitgame/audit.jsonl`.

Network:
- HTTPS on `10.0.2.2:7531` (or whatever the virtio bridge address
  is); mTLS required; no `0.0.0.0` bind.
- Only outbound to `github.com:443`. Deny everything else via VM
  firewall.
- No SSH server.

---

## 10. What agents actually do (the new workflow)

Before GitGame:

```
agent edits file → agent runs `git add/commit/push` → fails on virtiofs →
  agent produces copy-paste block → operator reads, checks, runs, commits,
  pushes → drift if operator is away
```

After GitGame (Tier 1):

```
agent edits file (via file tools) → agent POSTs /games/propose with
  {file_changes, pr_title, pr_body} → GitGame validates, commits in its
  own clone, pushes agent branch, opens PR → receipt-land CI, receipt-
  hygiene CI, mac-cell-ci CI run on the PR → agent gets PR URL +
  receipt_id back → operator reviews PR → operator POSTs /games/ship with
  operator_sig → GitGame merges.
```

No index‑lock fights, no `Operation not permitted`, no stale
copy‑paste blocks going out of sync with the tree. Every step has a
receipt.

---

## 11. Failure modes and how GitGame handles them

- **Push conflict** (someone else pushed first): daemon rebases and
  retries at most once; if still conflicted, returns a `refuse`
  receipt with the conflict summary and the expected operator action.
- **CI red after PR opens**: receipt shows PR opened with `ci_status:
  red`; the agent sees the failure and can open a follow‑up
  `propose` with a fix.
- **Protected path touched without operator_sig**: `refuse` receipt
  with `refusal_reason: protected_path_without_signature`.
- **Receipt‑hygiene violation in the patch**: daemon refuses *before*
  push (runs the same Python walker that the CI gate runs), so CI
  never has to refuse.
- **Clock skew on signature verification**: reject with
  `refusal_reason: operator_sig_stale` (signatures older than 5 min
  are rejected).
- **VM outage**: agents queue requests with exponential backoff; the
  daemon processes queued requests in order on recovery. Queued
  requests older than 1 hour are auto‑refused.
- **Daemon key compromise**: operator rotates the signing key + the
  deploy key; all historical receipts remain valid because they're
  signed under the old key, but new receipts chain from the rotation
  receipt.

---

## 12. How this plays with work already landed

- **`receipt-hygiene.yml`** — GitGame runs the same walker locally
  before any push. CI remains the belt‑and‑suspenders gate.
- **`sparkle-release-lint.yml`** — GitGame runs
  `zsh GAIAOS/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh`
  before any `release` game and before any `propose` that touches
  `project.yml`. Two doors, same key.
- **`mac-cell-ci.yml`** — GitGame does not emulate it locally
  (headless macOS runner territory). It waits for the CI run to go
  green before allowing `ship`.
- **`gaiafusion-gamp5-validation.yml` → `build‑smoke`** — same
  treatment as `mac-cell-ci.yml`.
- **KERNEL DEADLOCK PROTOCOL** — GitGame explicitly documents itself
  as a **software‑provenance** daemon (`M_SIL`). It never claims
  operator OQ / PQ. `ship` games require a fresh operator
  co‑signature, which is the operator crossing the Aqua boundary, not
  GitGame.

---

## 13. Open questions for the operator

One round of decisions to finalize before Phase 1 build starts:

1. **Merge policy:** fast‑forward only, or allow squash / rebase on
   `ship`? Recommendation: `fast-forward` only for `main`; squash is
   allowed on feature‑to‑feature merges only.
2. **Sig cache window:** how long is an `operator_sig` valid?
   Recommendation: 5 minutes, no cache. Every `ship` requires a
   fresh signature.
3. **Agent auth:** shared client cert for MVP (simpler), or per‑agent
   certs from day one (more forensic, more to manage)? Recommend per‑
   agent from day one — the CN → `invoked_by` mapping is cheap and
   invaluable in audits.
4. **Language:** Rust daemon or Python daemon? Recommend Rust (aligns
   with the MetalRenderer stance on hard‑gated Clippy and with the
   signing surface).
5. **Repo host:** does the Debian VM already have sufficient resources
   (disk, RAM) to hold a second clone + per‑game worktrees? If not,
   plan the resize in Phase 0.
6. **Scope of the wiki:** does the wiki repo live under GitHub's
   auto‑provisioned `<repo>.wiki.git`? If so, add `wiki-update` to
   Tier 2 with the same protected‑list story.

---

## 14. What "done" looks like

Phase 1 acceptance criteria:

- `POST /games/status` returns within 500 ms with correct branch /
  ahead / behind counts.
- `POST /games/propose` with a 3‑file change opens a PR that passes
  `receipt-hygiene.yml` + `mac-cell-ci.yml` (where applicable) on
  first try.
- `POST /games/ship` with a stale `operator_sig` returns a `refuse`
  receipt.
- `POST /games/ship` with a fresh `operator_sig` merges the PR and
  deletes the source branch.
- Every invocation writes a receipt under
  `evidence/gitgame/**`, and the on‑disk chain verifies from genesis
  through the latest receipt.
- No git command runs in the agent shell. Period.

---

## 15. Disclaimers

GitGame is a software‑provenance automation layer. It is **not**
operator OQ / PQ, **not** GAMP 5 qualification, and **not** a
regulatory artifact. It reduces friction and makes every agent action
auditable. The human operator remains the final gate on `main`.
