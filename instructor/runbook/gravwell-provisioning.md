# Gravwell provisioning

What works on a live lab host (Ubuntu, Docker 29 / Compose v5, `gravwell/gravwell:5.10.1`) as a
real seat user. The Lab 00 docker compose reflects this design.

## Fresh-host order of operations (scripts in `scripts/`)

1. `bootstrap-host.sh`, fresh Ubuntu/Debian host as root: docker (official repo), tooling,
   opencode (system-wide), `/opt/workshop`, image pre-pull, ufw rules, sysctl. Idempotent.
2. `issue-cert.sh step1` → add the TXT record → `issue-cert.sh step2`, Let's Encrypt, manual DNS-01.
3. `build-student-repo.sh`: generates `/opt/gitsrv/jarvis.git` from an allowlist + 
   `student-repo/checkpoints.yaml`. Regenerates lab data, strips instructor answers, asserts no
   leaks, tags 8 checkpoints, and verifies a fresh clone is non-empty before declaring success.
   **Run it before `makeuser.sh`**: the clone step needs the bare repo to exist.
4. `makeuser.sh`: seats. **Default 2 seats, ids 10–11** (`SEATS`, `START_ID`): the development
   and self-guided default; a delivery runs `SEATS=20 ./makeuser.sh`. Reads `/opt/workshop/.env`,
   and what you pass on the command line wins over what that file says.
5. `start-share-server.sh`: the share site (nginx in docker, HTTPS + basic auth on 80/443).
   Then, from the authoring box, `deploy-share.sh` ships the built PDFs into `staged/`. During the
   class an instructor releases them with `share.sh publish …`; **`staged/` is never served**, so
   unreleased material is unreachable rather than merely unlisted.
6. `preflight.sh`: read-only day-of checklist (host, secrets, cert, images, repo, seats, ports).
7. `rmuser.sh`: teardown by seat range (compose project label = `WORKSHOPUID`).

## Seat provisioning (`makeuser.sh`): works, with fixes (now applied in the script)

Created `workshop11` cleanly (docker group, env vars, git config). Apply these fixes to the script:

1. **Install `authorized_keys`** (script doesn't; needed for instructor/automation SSH):
   ```bash
   install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$USER_HOME/.ssh"
   cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/authorized_keys"
   chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh/authorized_keys"; chmod 600 "$USER_HOME/.ssh/authorized_keys"
   ```
2. **Env vars load only in interactive shells.** `export …` appended to `~/.bashrc` is skipped by
   the Ubuntu non-interactive early-return, so `ssh user@host 'cmd'` and `bash -lc` see empty values.
   Fine for students (interactive), but scripted steps must set `WORKSHOPUID` explicitly.
3. **Clone step** needs `/opt/gitsrv/jarvis.git`: run `build-student-repo.sh` first, or seats get
   no `~/jarvis` and every handout path fails.
4. **Rotate + de-hardcode** the `ANTHROPIC_API_KEY` (move to env/secret).

## Gravwell in docker: the validated design (in Lab 00's compose)

- **Named volumes** `gwetc` + `gwstorage` for persistence. Do **not** bind-mount `/opt/gravwell/etc`:
  an empty bind mount shadows the image configs (won't boot); bind mounts don't inherit image
  contents (need seeding); the root container writes root-owned files into the student's home; and
  a pre-seeded `etc` makes the image ignore env config. Named volumes avoid all four.
- **License is mandatory.** A fresh instance returns `{"Error":"missing license"}` for login *and*
  ingest, and the indexer never opens its pipe. Mounted read-only from
  `gravwell.license` at the repo root → `/opt/gravwell/etc/license`. (Validated:
  license installed → login works, indexer pipe appears, ingest flows. A Community Edition license
  has `MaxNodes:1`, which is per standalone instance, so each student's isolated container is its
  own valid node. `SETUP.md` covers obtaining one; the file is git-ignored.)
- **HTTPS on 443.** The image defaults to HTTP on :80 and ignores `GRAVWELL_WEB_PORT`. We override
  via a `gravwell.conf.d/https.conf` drop-in (`[global]` `Web-Port=443`, `Insecure-Disable-HTTPS=false`,
  `Certificate-File`/`Key-File`) + a mounted cert/key. Validated with a self-signed cert
  (`CN=<lab-host>`); swap in the Let's Encrypt cert for production (below).
- **Ingest auth: set BOTH env vars or neither.** `GRAVWELL_INGEST_AUTH` configures the *indexer*,
  `GRAVWELL_INGEST_SECRET` configures the bundled *simple_relay*. The compose now sets both from
  `GRAVWELL_INGEST_SECRET` in `.env` (default `IngestSecrets`); the LLM-ingester sidecar uses the same
  value.

## Ingest: `simple_relay` (validated)

No `reimport`/`oneshot` tool ships; ingest is via `gravwell_simple_relay` with a
`simple_relay.conf.d/` drop-in (`config/simple_relay-corelight.conf`) that adds one line-delimited,
`Ignore-Timestamps=true` listener per Corelight tag on 7701–7704 (published as `${WORKSHOPUID}01`–`04`).
Students ingest each per-tag JSONL file:

```bash
nc localhost ${WORKSHOPUID}01 < corelight_dns.jsonl    # + 02/ssl, 03/conn, 04/http
```

**Validated:** after `nc`, `GET /api/tags` (Bearer JWT from `POST /api/login`) returns
`corelight_dns`, `corelight_ssl`, `corelight_conn`, `corelight_http`. `Ignore-Timestamps=true` gives
current-time ingest (search "last 15 min"), matching the pre-flight checklist.

## LLM-ingester sidecar (M9): validated locally

- Official image `gravwell/llm_ingester:5.10.1` (21 MB). Env: `GRAVWELL_INGEST_SECRET`,
  `GRAVWELL_CLEARTEXT_TARGETS=gravwell:4023` (compose-network hostname; 4023 is not published).
- Listeners come from `labs/00-environment-gravwell/config/llm_ingester.conf` (`:4180` openai-chat,
  `:4181` anthropic-messages, both → `https://api.anthropic.com`, `Tag-Name = llm`).
- **Gotcha:** the binary rewrites its config on boot to stamp an `Ingester-UUID` (temp file +
  `rename`). A read-only bind mount makes it exit 1 in a loop (`device or resource busy`) and the
  manager gives up after 3 restarts for 10 min. Fix in the compose: mount at `/config/` and
  `cp` into `/opt/gravwell/etc/` before `exec manager`.
- Validated with the mock provider (`scripts/mock_llm_upstream.py`): buffered + streaming on both
  protocols, tool calls (arguments reassembled), `x-claude-code-session-id` adopted as session id,
  usage records. `tag=llm` appears; `tag=llm intrinsic event_type … | table …` returns everything.
- The Python proxy (`src/logging-proxy/llm_audit_proxy.py --tcp localhost:<ID>05`) lands under
  `tag=proxy` via the new `simple_relay-proxy.conf` listener (7705 → `<ID>05`). Validated.

### API tokens: what every script authenticates with (validated on 5.10.1)

Nothing in the course logs in with a password any more. Lab 00's `make-token.sh` mints one API
token per seat; scripts read it from `~/.gravwell_token`, which `~/.workshop_env` exports as
`$GRAVWELL_TOKEN`. The reason is a first-delivery failure: a student who changed the admin password
broke every script that logged in as `admin`/`changeme`, with errors that pointed nowhere useful.

The endpoints (the product docs describe the UI path only, so these were read off a live instance):

| Call | Shape |
|---|---|
| `GET /api/tokens/capabilities` | the capability names this build supports (**51** on 5.10.1) |
| `POST /api/tokens` | `{"Name":…,"Description":…,"Capabilities":[…]}` → the response carries `token`, **once**; Gravwell never shows it again |
| `GET /api/tokens` | lists tokens (id, name, capabilities), never the secret |
| `DELETE /api/tokens/<id>` | revoke, 204 |

**Verified facts:**

- The header is **`Gravwell-Token: <token>`**. The same string as `Authorization: Bearer` is a
  **401**: that header is for a login JWT only.
- Capabilities really are enforced per endpoint, and the refusal names the missing one:
  `{"Cap":"LogbotAI","Error":"Access denied, missing capability"}`. **`/api/mcp` needs `LogbotAI`**;
  kits need `KitRead`/`KitWrite`; `/api/tokens` needs `TokenRead`.
- `make-token.sh` grants everything **except** `TokenRead`/`TokenWrite` (49 of 51), so a leaked
  token cannot mint a replacement. Capabilities are an overlay on the user's permissions: subtract
  only, never add.
- A token **survives a password change**: with the admin password changed, `/api/login` returns 401
  while the token still answers `/api/resources`, `/api/search/direct` and `/api/mcp` with 200.
- A token lives in the instance's volumes, so `docker compose down -v` destroys it. `make-token.sh`
  detects a dead token and mints a new one, which is what a seat rebuilt mid-course runs.

### Validating ingest from the CLI (no UI needed)
```bash
GW=https://localhost:${WORKSHOPUID}443; AUTH="Gravwell-Token: $GRAVWELL_TOKEN"
curl -sk $GW/api/tags -H "$AUTH"
START=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ); END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl -sk -X POST $GW/api/search/direct -H "$AUTH" -H 'content-type: application/json' \
  -d "{\"SearchString\":\"tag=llm intrinsic event_type | count by event_type | table event_type count\",\"SearchStart\":\"$START\",\"SearchEnd\":\"$END\",\"Format\":\"csv\"}"
```
(`/api/search/direct` wants RFC3339 times in `SearchStart`/`SearchEnd`; `table` needs
`"Format":"csv"`, not `text`.)

## Let's Encrypt (TLS for the venue)

Students browse from the venue ISP to the lab host's IP with no SSH wrapper, so the UI must be real-cert
HTTPS. **One LE cert for the lab host's DNS name serves every student instance**, a cert is
per-hostname and port-independent (`:11443`, `:12443`, …).

Issued via **DNS-01** with acme.sh in manual mode, which works with any DNS provider and needs no
registrar API. `scripts/issue-cert.sh step1` / `step2` wrap these commands:

```bash
# install + register (one time)
git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /root/acme.sh-src
cd /root/acme.sh-src && ./acme.sh --install -m <email> --home /root/.acme.sh
/root/.acme.sh/acme.sh --server letsencrypt --register-account -m <email>

# 1) generate the challenge (prints the TXT record and exits: non-blocking)
/root/.acme.sh/acme.sh --server letsencrypt --issue --dns -d <lab-host> \
  --yes-I-know-dns-manual-mode-enough-go-ahead-please
# 2) add TXT _acme-challenge.<lab-host> = <printed value> at your DNS provider, then:
/root/.acme.sh/acme.sh --server letsencrypt --renew -d <lab-host> \
  --yes-I-know-dns-manual-mode-enough-go-ahead-please
```

**Cert location:** `/opt/workshop/certs/{cert.pem,key.pem}`, **root-owned**, `key.pem` is `0600`.
The docker daemon (root) performs the bind mount, so every student's container gets the cert while
students **cannot read the private key**. Seats receive `WORKSHOP_CERT_DIR=/opt/workshop/certs` via
`~/.workshop_env`; the compose falls back to `./config/` for self-hosted students.

**No renewal: this is a one-shot init.** The lab instance is disposable (torn down after the
workshop), so we deliberately do **not** auto-renew. The acme.sh renewal cron was removed
(`/root/.acme.sh/acme.sh --uninstall-cronjob`), and there is no reload/deploy hook to maintain.
A Let's Encrypt cert is valid for 90 days, which covers a delivery with margin.

If the host is ever rebuilt, just **repeat the two issuance steps above**, that *is* the init.
(acme.sh can't renew a manual-DNS cert unattended anyway; each issue needs a fresh
`_acme-challenge` TXT value.) The leftover `_acme-challenge` TXT record can be deleted once the
cert is issued.

**Verified:** `curl` *without* `-k` to `https://<lab-host>:11443/` returns 200, and the presented
cert is `CN=<lab-host>`, issuer `Let's Encrypt`. Browser-trusted.

## Full validated flow (fresh volumes)
`docker compose up -d` → HTTPS 200 on `${WORKSHOPUID}443`, licensed login, 4 ingest listeners bound;
`nc` the four files → all four `corelight_*` tags present. Confirmed on a from-scratch volume.

