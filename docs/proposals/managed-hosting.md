# Proposal — managed hosting and the management API

**Status:** draft for discussion, 2026-09-18. Nothing here is decided. Several
parts need a decision from Matt before any code moves, because they touch
SPEC §2 anti-goals, AGENTS hard rules and settled entries in
`docs/decisions.md` (see §1).

**Goal:** a person who does not want to run a box can get a Linger server
from the Linger website with one button, and manage it afterwards from a web
console: status, logs, backups, updates, wiping, clearing media, password
recovery, and the other jobs a self-hoster does today over SSH. The
provisioning must work across more than one cloud provider, and every new API
is documented with OpenAPI (Swagger).

---

## 1. Gates — decide these before building

These are not implementation details. Each one contradicts something the repo
currently says, and AGENTS.md ("When to stop and ask") requires the docs to
change first.

| # | Conflict | Where it is written | What has to be decided |
|---|---|---|---|
| G1 | **Selling hosting is a payment surface.** | SPEC §2 anti-goals ("a paid tier … or any payment surface at all"), AGENTS rule 14, README "no company in the middle" | Whether a hosted offering exists at all. If it does: it lives in a **separate repo and service**, billing never enters this repo or the app, and the hosted server is the same free software with nothing held back. The README's "case for running your own" needs an honest paragraph about the hosted option. |
| G2 | **A host-facing settings endpoint "will not exist".** | `docs/decisions.md` — *the host's side* (storage knobs are env vars) | This proposal keeps that decision: knobs stay env vars; the console changes them by rewriting the environment and restarting. The new API is a *management* API on a private port, not a host endpoint. Needs a line in decisions.md saying so. |
| G3 | **"Do not build a backup feature."** | ARCHITECTURE §9 | A hosted service without backups is negligent. Proposal: the server gains one primitive — a consistent snapshot of the database — and everything else (schedules, storage, retention) lives in the hosting control plane, outside this repo. |
| G4 | **"No env-var bootstrap credentials."** | ARCHITECTURE §9, PROTOCOL §2.1 | The setup link is still one-time and still minted by the server. The management API only *reads it out* instead of the host scraping `docker compose logs`. No password is ever set from env. |
| G5 | **Vocabulary.** "Admin" and "owner" are banned words for the host. | SPEC §1, AGENTS rule 6 | A new term for the hosting company's side. Proposed: **operator** (the people running the hosting service) and **the console** (the website UI). The customer inside the app stays **the host**. Add to SPEC §1. |
| G6 | **Threat model.** "The person running the server can read everything on it." | ARCHITECTURE §7, README | On a hosted server, the operator is that person. The signup page must say so verbatim. The management API deliberately has **no endpoint that reads messages or file contents** — but disk access exists, so never claim the operator *cannot* read. |
| G7 | **No telemetry.** | AGENTS rule 4, SPEC §2 | Management status must be *capacity* figures only (disk, storage pool, database size, version, uptime). No message counts, activity, who is online, or anything that measures engagement. Pulled on demand by the console, never pushed home. |
| G8 | **No host transfer.** | `docs/decisions.md` | The website account (the customer) and the in-app host account are different things. Recovery is "reset the host's password", not "make somebody else host". |

---

## 2. What exists today

The server already does more of this than it looks, but almost all of it is
reachable only by a person with a shell on the box.

| Job | Today | Reachable remotely? |
|---|---|---|
| First-run setup link | Printed to stdout at boot (`main.rs`, `setup.rs`) | No — read from `docker compose logs` |
| Reset a forgotten password | `linger-server reset-password` CLI (`reset.rs`); server must be stopped | No |
| Health | `GET /api/v1/health` → `{ok, version}` | Yes, public |
| Storage used / limit / expiry | In `GET /api/v1/server` (`ServerInfo`) | Yes, any member |
| Rename server, rooms, invites, remove/restore members | In-app host routes (`HostUser`) | Yes, as the host, in the app |
| File expiry sweep | Background task every 6 h (`expiry.rs`) | No manual trigger |
| Full export (zip) | `POST /api/v1/export`, any member | Yes, as a member |
| Storage knobs | Env vars read once at boot (`config.rs`) | No — edit compose, restart |
| Logs | `tracing` to stdout; only the setup line names a person | No — `docker compose logs` |
| Backup | Documented as copy `linger.db` + `objects/` | No |
| Update | `docker compose pull && up -d` | No |
| Wipe | Delete `./data` | No |
| Sign everyone out | Not possible (JWT key loaded once from `data/jwt_ed25519.pk8`) | — |
| Delete a member's data | Not possible — removal keeps the account row by design | — |
| OpenAPI | None. PROTOCOL.md is prose; wire types go to TS via `ts-rs` | — |

Shape facts that drive the design:

- **One process, one SQLite file, one writer** (`db.rs`). Anything that writes
  must go through `Db::write` while the server runs, or the server must be
  stopped. Hosting is therefore **one Linger process per customer** — no
  shared database, no multi-tenancy inside the binary. That is correct and
  should not change.
- **Config is env-only and read at boot.** Changing a knob means a restart.
- **The JWT signing key is loaded once** into `AppState`. Rotating it needs it
  behind a swappable handle.
- **Migrations are forward-only** (`sqlx::migrate!`). Rolling back a version
  after a migration ran means restoring a snapshot, not running the old image.
- **The S3 backend has no key prefix.** One bucket per server, or a new
  `LINGER_S3_PREFIX`.

---

## 3. Architecture

Three pieces. Only the first lives in this repo.

```
┌──────────────────────── Linger website (separate repo) ───────────────────┐
│  Console UI  ──►  Control-plane API (OpenAPI)  ──►  job queue             │
│                        │                             │                    │
│                        │                             ├─ OpenTofu runs     │
│                        │                             │  (VMs, disks, DNS) │
│                        ▼                             ▼                    │
│                  customer DB, audit           backup bucket               │
└────────────────────────┬──────────────────────────────────────────────────┘
                         │ mTLS / signed requests, private network or tunnel
        ┌────────────────▼─────────── one customer VM ────────────────────┐
        │  linger-agent  (docker access: restart, update, logs, snapshot  │
        │                 upload, wipe, env changes)                      │
        │        │ localhost only                                         │
        │        ▼                                                        │
        │  linger-server ── public :8420 via Caddy (unchanged)            │
        │               └── management listener 127.0.0.1:8421            │
        │                   (NEW, off by default)                         │
        │  caddy · coturn  (the same deploy/compose.yaml self-hosters use)│
        └─────────────────────────────────────────────────────────────────┘
```

**Why split agent and server.** Some jobs can only be done from inside the
process (anything touching the live database through the single writer, the
setup token, the JWT key, connected sessions). Others can only be done from
outside it (restart, pull a new image, read container logs, delete the data
directory). Putting the outside jobs in the server would mean giving it the
Docker socket, which is a bad trade.

### 3.1 The management API (this repo, `linger-server`)

The server's private API for jobs that must happen inside the running
process. Nobody calls it directly: a customer's click in the console and an
operator's action both arrive as control-plane jobs (§6), and the control plane
decides who may do what before any step reaches the server. The server only
checks that a request was signed by the control plane.

- **Separate listener**, `LINGER_MANAGE_BIND` (e.g. `127.0.0.1:8421`). Unset =
  no listener, no routes, nothing compiled into the public router. A
  self-hoster's server is byte-for-byte the same surface as today.
- **Never behind Caddy.** Only the agent on the same machine calls it.
- **Auth:** `LINGER_MANAGE_PUBLIC_KEY` (Ed25519). Each request carries a short-lived
  token signed by the control plane, with audience = `LINGER_SERVER_ID`,
  expiry ≤ 60 s and a nonce the server remembers until expiry. Loopback-only
  is not enough on its own: any process on the box could call it.
- **Destructive calls are two-step:** `POST …/wipe` returns a confirmation id;
  a second call with that id within 60 s executes. Stops a retried request or
  a stray click from wiping a server.
- **Audit:** every management call writes a row to a new `manage_audit` table
  (time, action, parameters, result). Proposed follow-up: the host can read it
  in the app, so a customer can see everything the hosting service did to
  their server. That is the strongest trust signal available and costs one
  read-only route.
- **Nothing reads content.** No endpoint returns messages, file bytes, DM
  membership, usernames lists, presence or activity. Capacity numbers only.

### 3.2 The agent (hosting repo)

Small daemon on each VM (Rust or Go) with the Docker socket. Talks outward to
the control plane over mTLS (outbound only, so the VM exposes no management
port). Jobs: restart, set env + recreate, pull and switch image tag, stream or
bundle logs, trigger a server snapshot and upload it with the objects, restore
a snapshot, wipe the data directory, report disk and certificate expiry.

### 3.3 The control plane (hosting repo)

Customer accounts, the console UI, the public control-plane API, the
provisioning queue, backup storage and retention, and anything to do with
money if G1 allows it. Its API is documented with OpenAPI too.

---

## 4. Provisioning — tool choice

**Recommendation: OpenTofu** (the open-source fork of Terraform — same HCL,
same providers, MPL-licensed), **one module per cloud behind one shared
interface**, and **cloud-init that runs the existing `deploy/compose.yaml`.**

Be clear-eyed about what "generic across clouds" means with any of these
tools: none of them hides the provider. An AWS instance and a Hetzner server
are different resources with different arguments. Portability comes from
*you* defining a small contract and writing one implementation per provider:

```
modules/
  linger-host/            # the contract: inputs + outputs, no resources
  linger-host-hetzner/    # hcloud_server + hcloud_volume + firewall
  linger-host-digitalocean/
  linger-host-aws/        # ec2 + ebs + security group (or Lightsail)
  dns-cloudflare/         # one DNS provider regardless of compute cloud
  cloud-init/             # installs docker, writes compose + .env, starts
```

Inputs: `server_id`, `region`, `size`, `domain`, `image_tag`, `manage_public_key`,
`agent_cert`. Outputs: `ipv4`, `ipv6`, `volume_id`. Everything above the
module line — the agent, the compose file, the Linger image — is identical on
every cloud. That is the real portability, and it is why the per-customer box
should look exactly like a self-hosted one.

Options considered:

| Tool | Verdict |
|---|---|
| **OpenTofu / Terraform** | **Recommended.** Largest provider coverage, the team can read it, state is plain files in an S3-compatible bucket. Terraform itself is fine too; its BSL licence only bites if you sell Terraform. |
| **Pulumi** | Strong alternative. Same provider model, but infrastructure in TypeScript/Go, and its *Automation API* lets the control plane run provisioning as a library call instead of shelling out. Pick this if the control plane is TypeScript and nobody wants HCL. |
| **Kubernetes (+ Helm / Crossplane)** | Not now. Managed k8s exists on every cloud, but the voice relay wants host networking and a UDP port range, SQLite wants exactly one pod on one disk, and a cluster is a lot of machinery for a small team. Revisit at hundreds of servers. |
| **Nomad** | Good later, for packing many customer servers onto shared hosts (§8, phase 6). Handles host networking cleanly. |
| **Ansible** | Unneeded — cloud-init plus containers covers configuration. |
| **CloudFormation / Bicep / Deployment Manager** | Single-cloud by definition. No. |

**Per-customer VM first.** A 1 vCPU / 1–2 GB VM costs roughly $4–12 a month
depending on provider. It gives clean isolation, the voice relay works with no
port juggling, a restore is "attach the disk to a new VM", and it runs the same
compose file the host guide documents — so hosting doubles as a continuous
test of the self-host path. Pack onto shared hosts later if cost demands it.

**Do not run `tofu apply` inside a web request.** The console enqueues a job;
a worker runs it with one state file per customer server, and the console
polls the job.

Domains: default `<name>.<hosting-domain>` plus `cdn.<name>.<hosting-domain>`
(the server requires a separate media host — ARCHITECTURE §7). Custom domains
later via CNAME and Caddy on-demand TLS.

---

## 5. The APIs

### 5.1 Management API — new, in `linger-server` (`/manage/v1`, management listener only)

| Method | Path | What it does | Notes |
|---|---|---|---|
| GET | `/status` | version, schema version, uptime, db + WAL bytes, objects bytes, pool limit, expiry days, member count, disk free, last sweep, whether setup is pending | Capacity only (G7) |
| GET | `/setup-link` | The current one-time setup URL, or 404 if set up | Replaces reading logs (G4) |
| POST | `/hosts/reset-password` | Generate a new host password, sign the host out everywhere, return it once | Reuses `reset.rs`; works live through `Db::write`, so no stop needed |
| POST | `/sessions/revoke-all` | Revoke every refresh token, rotate the JWT key, close every gateway session | "Somebody's account got stolen" button. Needs `JwtKeys` behind `ArcSwap` |
| POST | `/invites/revoke-all` | Revoke every open invite | |
| POST | `/media/sweep` | Run the expiry sweep now | Wraps `expiry::sweep` |
| POST | `/media/purge` | Delete files: all, or older than N days, optional `include_starred` | Two-step. Same "bytes first, row second" path as expiry. Clients must be told the files are gone |
| DELETE | `/media/objects/{attachment_id}` | Remove one file by id | Abuse / legal takedown without browsing content |
| POST | `/exports/purge` | Delete every export archive | Frees disk; members can ask again |
| POST | `/snapshot` | Write a consistent copy of the database (`VACUUM INTO`) into `data/snapshots/`, return path + checksum | The one backup primitive (G3). The agent uploads it with the objects |
| POST | `/wipe` | Two-step. Only callable after the agent has snapshotted; the agent does the actual stop / delete / start | Server side is confirmation + audit. After restart the server has no users, so `/setup-link` returns a fresh link |
| GET | `/audit` | The management audit log | |
| GET | `/openapi.json` | This API's spec | Also committed to the repo, drift-checked in CI |

Deliberately **not** here: changing pool size, expiry or TURN settings (env
vars, changed by the agent, per decisions.md — G2); restart and update (the
agent); logs (container stdout, read by the agent).

### 5.2 Control-plane API — new, hosting repo (what the console calls)

Two kinds of call. **Reads** (status, logs tail, backups list, audit) answer
directly. **Everything that changes something is a job**: the console calls
`POST /servers/{id}/jobs` with a kind and parameters, gets a job id back, and
polls `GET /jobs/{id}` for step-by-step progress. §6 defines every job kind.

| Area | Endpoints (sketch) |
|---|---|
| Servers | create, list, get, rename domain, suspend, resume, delete (with a final full-data download offered and a grace period) |
| Status | status (proxied from `/manage/v1/status` + agent disk/cert data) |
| Lifecycle | restart; update to version; pin version; roll back = restore the pre-update snapshot |
| Logs | tail (last N lines), download bundle for a time range, set log level |
| Backups | list, create now, schedule + retention, download, restore; **"take it home"**: download `linger.db` + `objects/` as a tarball that runs on the self-host compose file unchanged |
| Import | upload a self-hosted backup to start a hosted server from it |
| Settings | storage pool, file expiry, voice relay on/off — env changes + restart |
| Data | wipe, purge media, sweep now, purge exports, remove one file |
| Access | reset host password, get setup link, sign everyone out, revoke all invites |
| Audit | everything the console and operators did to this server |

### 5.3 OpenAPI / Swagger

- **Generate the spec from the code, don't hand-write it.** Use `utoipa`
  (derive macros on handlers and types) with `utoipa-axum`. Hand-written YAML
  drifts from the code the same way hand-written TS types would (AGENTS rule 7
  exists for that reason).
- Management request/response types live in `linger-core` (rule 7), under a new
  `manage` module, deriving both `ts-rs::TS` and `utoipa::ToSchema` — the latter
  behind a `openapi` cargo feature so the desktop client never compiles it.
- A test writes `docs/openapi/manage-v1.json`; it is committed and CI fails on
  drift, exactly like `client/src/generated/`.
- Swagger UI is served by the **website**, not by `linger-server` — keeps the
  server small and keeps a docs page off every customer's box. (The management
  listener can serve raw `openapi.json` for the agent.)
- PROTOCOL.md gains a *Management API* section that states the rules (auth,
  two-step, no content) and points at the JSON for the field list.
- Optional, separate decision: backfill OpenAPI for the public `/api/v1` too.
  Useful, but a large job, and PROTOCOL.md stays the source of truth.

---

## 6. Workflows

Every console action becomes a **job** in the control plane: a named
workflow with ordered steps, run by a worker, with its progress stored so it
survives a control-plane restart. The customer never touches the VM; the
console only starts jobs and shows their progress.

### 6.1 Rules every job follows

1. **Check, then record.** The control plane confirms the caller may run this
   job on this server (customer owns it, or operator has the role), then writes
   the job and an audit row *before* any step runs.
2. **One changing job per server at a time.** A per-server lock. A second
   request waits in the queue or is refused with "another job is running";
   reads are never blocked.
3. **Idempotency key.** The console sends one per click, so a double-click or a
   retried request cannot start the same job twice.
4. **Every step can be safely retried.** A worker that crashes mid-step picks
   the job up again and repeats the step; the step must give the same result
   the second time (e.g. "ensure stopped", not "stop").
5. **Snapshot before anything destructive.** Wipe, purge, restore, update and
   delete all take a backup first. If the backup fails, the job stops before
   touching data.
6. **End with a health check.** Any job that restarts the server finishes by
   calling `/api/v1/health` and `/manage/v1/status`; a failed check triggers
   the job's failure plan, not a "success" with a broken server.
7. **Destructive jobs confirm twice.** In the console (type the server name),
   and at the server (the management API's two-step confirmation).
8. **States:** `queued → running → succeeded | failed | rolled_back`, each step
   recorded with its start, end and result. The customer sees the step list.

Actors in the tables: **C** console · **CP** control plane · **T** OpenTofu
worker · **A** agent on the VM · **S** server management API.

### 6.2 Access

**Get setup link** — customer. Not a job; a read.
CP → A → S `GET /setup-link`. 404 means already set up; the console says so.

**Reset host password** — customer, operator.
1. CP: audit, lock.
2. S `POST /hosts/reset-password` → new password, host signed out everywhere.
3. C: show the password once. It is not stored in the control plane.
Failure: nothing changed; show the error.

**Sign everyone out** — customer, operator.
1. S `POST /sessions/revoke-all` (refresh tokens revoked, JWT key rotated,
   gateway sessions closed).
2. C: "Everyone, including you, has to sign in again."

**Revoke all invites** — customer, operator. S `POST /invites/revoke-all`.

### 6.3 Data

**Clear media** — customer, operator. Parameters: all, or older than N days;
include starred files or not.
1. C: show what will go (count and size from `/status`), confirm by name.
2. A + S: snapshot database; A copies the object list with it.
3. S `POST /media/purge` (two-step), in batches.
4. C: report files removed and space freed.
Failure mid-purge: stop; already-deleted files stay deleted; the snapshot
restores the rows if the customer wants them back, but bytes deleted from disk
are only recoverable from the most recent full backup.

**Sweep media now** — customer, operator. S `POST /media/sweep`. Report result.

**Remove one file** — operator only (abuse / legal takedown).
1. CP: record the report reference with the job.
2. S `DELETE /media/objects/{id}`.
3. CP: remove the same object from backups inside the retention window.

**Delete export archives** — customer, operator. S `POST /exports/purge`.

**Wipe server** — customer, operator.
1. C: confirm by typing the server name.
2. A + S: full backup (database snapshot + objects), uploaded and checksummed.
   Kept for the normal retention period so a wipe is recoverable.
3. S `POST /wipe` → confirmation id; S `POST /wipe` with the id.
4. A: stop the container, delete the data directory, start it.
5. Health check. S `GET /setup-link` → new link.
6. C: show the new setup link.
Failure before step 4: nothing lost. After step 4: server is empty; restore
from step 2's backup is offered.

### 6.4 Backups

**Back up now** (and the scheduled version) — customer, operator.
1. S `POST /snapshot` → database file + checksum.
2. A: upload the snapshot and the objects (only new objects since the last
   backup) to the backup bucket.
3. CP: record the backup; apply retention (e.g. 7 daily, 4 weekly).
Failure: mark failed and alert operators; a missed backup is never silent.

**Restore a backup** — customer, operator.
1. C: pick a backup, confirm by name.
2. Take a fresh backup of the current state first (rule 5).
3. A: stop, replace the database and objects with the chosen backup, start.
4. Health check. The server runs migrations if the backup is older.
Failure: restore the backup from step 2.

**Download my data ("take it home")** — customer.
1. Take a fresh backup.
2. A or CP: build a tarball of `linger.db` + `objects/` with a README saying
   how to run it on `deploy/compose.yaml`.
3. C: time-limited download link.

**Import a self-hosted server** — customer.
1. C: upload the tarball (straight to the backup bucket).
2. CP: check it — the database opens, its schema version is not newer than
   the hosted image.
3. Run *Create server* with this backup as the starting data.

### 6.5 Lifecycle

**Create server** — customer.
1. CP: reserve the name, generate `LINGER_SERVER_ID`, agent certificate and
   TURN secret.
2. T: `tofu apply` for this server's workspace — VM, disk, firewall, DNS for
   the name and `cdn.` name.
3. Cloud-init on the VM: install Docker, write compose and `.env`, start
   Linger, Caddy, coturn and the agent.
4. A: connects to CP (this is how CP knows the VM is up).
5. Wait for Caddy's certificate; health check.
6. S `GET /setup-link` → C shows it.
Failure: `tofu destroy` the partial server and free the name.

**Restart** — customer, operator.
A: restart the Linger container → health check. Failure: alert operators.

**Update to a version** — customer, operator (and scheduled by operators).
1. Take a backup (the rollback point).
2. A: pull the new image, recreate the container. Migrations run at start.
3. Health check.
Failure: A switches back to the old image **and** restores the step-1 backup —
the old image cannot run on a database the new one migrated. State:
`rolled_back`.

**Change settings** (storage limit, file expiry, voice relay) — customer,
operator.
1. CP: validate (e.g. the storage limit is not below what is already used).
2. A: write `.env`, recreate the container (and start or stop coturn).
3. Health check; confirm `/status` shows the new values.
Failure: A restores the previous `.env` and restarts.

**Change domain** — customer.
1. C: customer adds the DNS records (CNAME for the domain and `cdn.` name).
2. CP: check the records resolve to this server.
3. A: set `LINGER_DOMAIN`, update the Caddyfile, restart; wait for the
   certificate.
4. Health check on the new name.
Note: every client has the old address saved. The console says so, and the
old name keeps working until the customer removes it.

**Suspend / resume** — operator only.
Suspend: A stops the Linger container; Caddy serves a plain "this server is
paused" page. Data is untouched. Resume: A starts it; health check.

**Delete server** — customer, operator.
1. C: confirm by name; offer *Download my data* first.
2. Take a final backup, kept for a stated grace period (e.g. 30 days).
3. T: `tofu destroy` — VM, disk, DNS.
4. After the grace period, CP deletes the final backup and records that it did.

### 6.6 Reads (not jobs)

| Read | Path |
|---|---|
| Status | S `/status` + A disk and certificate expiry |
| Logs tail | A: last N lines of container output |
| Logs download | A: bundle a time range, upload, time-limited link |
| Backups | CP: list, sizes, times |
| Jobs | CP: this server's jobs and their steps |
| Audit | CP audit log + S `/audit` |

---

## 7. Changes needed in this repo

| # | Change | Files | Size |
|---|---|---|---|
| R1 | Docs first: G1–G8 resolved in SPEC §1/§2, ARCHITECTURE §7/§9, decisions.md, PROTOCOL (new section), README | docs | S |
| R2 | Management listener + config (`LINGER_MANAGE_BIND`, `LINGER_MANAGE_PUBLIC_KEY`, `LINGER_SERVER_ID`) + signed-token auth + nonce cache | `config.rs`, `main.rs`, new `manage/` | M |
| R3 | `manage_audit` migration + two-step confirmation store | `migrations/0006_manage.sql`, `manage/` | S |
| R4 | `utoipa` wiring, `linger-core::manage` types, spec file + CI drift check | `linger-core`, `scripts/check.sh`, `ci.yml` | M |
| R5 | `/status`, `/setup-link`, `/audit` | `manage/` | S |
| R6 | Live password reset (refactor `reset.rs` to run on `Db::write`) | `reset.rs`, `manage/` | S |
| R7 | Swappable JWT key + revoke-all + close all gateway sessions | `auth.rs`, `state.rs`, `gateway/` | M |
| R8 | Media purge / single-object removal / sweep-now / export purge, with gateway events so clients drop the files | `expiry.rs`, `repo/attachments.rs`, `export.rs` | M |
| R9 | `/snapshot` via `VACUUM INTO` | `manage/` | S |
| R10 | Structured logs: `LINGER_LOG_FORMAT=json` | `main.rs` | S |
| R11 | `LINGER_S3_PREFIX` (only if shared buckets are wanted) | `config.rs`, `storage/s3.rs` | S |
| R12 | Integration tests: every management route over real HTTP against a temp SQLite file (AGENTS testing rule), plus auth refusal cases (no token, wrong audience, expired, replayed, public port) | `tests/manage_*.rs` | M |

Not in this repo: agent, control plane, OpenTofu modules, console UI, billing.

---

## 8. Phases

1. **Decide (G1–G8).** Docs change. No code until this lands.
2. **Management API in the server** (R2–R12). Shippable on its own: nothing
   changes for self-hosters because the listener is off by default.
3. **Infrastructure.** OpenTofu modules for two providers (suggest
   DigitalOcean, already in `docs/vps-setup.md`, and Hetzner for price) +
   Cloudflare DNS + cloud-init. Milestone check: one command creates a working
   server on each provider, `/setup-link` returns a link, a desktop client
   joins it, and voice connects across two networks (AGENTS: realtime needs
   real-network proof).
4. **Agent + control plane.** Job queue, lifecycle, logs, backups with a
   **tested restore** (a backup nobody has restored is not a backup), update
   with automatic pre-update snapshot and rollback.
5. **Console UI** on the website, calling the control-plane API only.
6. **Hardening.** Abuse/takedown process, account-deletion flow, restore
   drills on a schedule, suspended-server behaviour, shared-host packing with
   Nomad if per-VM cost is a problem.

---

## 9. Open questions

- G1 above — whether this exists, and who decides (AGENTS names Matt).
- Is the console for customers only, or also for operator staff with a
  cross-server view? The API design is the same; permissions differ.
- Should a member be able to ask for their own data to be deleted? Hosting for
  strangers brings privacy law (the operator becomes a data processor), and
  today the only option is removal, which keeps the account row.
- Local disk plus volume snapshots, or S3 storage per server? Local is
  simpler for phase 3; S3 makes restores and moves faster.
- Which providers first, and in which regions.
