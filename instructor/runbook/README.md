# Instructor runbook

Host provisioning and day-of operations. Assumes a **fresh cloud host (Ubuntu/Debian), root**.

> **Weeks before a delivery, send the attendees
> [`materials/attendee-prerequisites.md`](../../materials/attendee-prerequisites.md)** with the
> abstract. It is the destinations list their security team needs to approve, and it is the
> difference between a room that can reach its seats at 09:00 and a room that cannot. A corporate
> exception takes days.

> **The morning of a delivery, work from [`class-day.md`](class-day.md).** It is the ordered
> sequence that takes the host from "we have been testing on it" to "students walk in": what the
> testing left behind, the reset in order, the venue IP whitelist, and the `release` / `share`
> commands you run as the class progresses. The table below is the reference; that page is the
> script.

**Short names:** `. instructor/runbook/.runbookrc` (once per shell, or from `~/.bashrc`) puts the
scripts on `PATH` and wraps the host-side ones in ssh, `redeploy`, `release --next`,
`share publish labs/02-shadow-ai html`, `preflight`, `reset-seat 10`, `seat 14`.

| Step | Script / doc | Notes |
|---|---|---|
| 1 | `scripts/bootstrap-host.sh` | docker, tooling, opencode, `/opt/workshop`, image pre-pull, firewall rules. Idempotent |
| 2 | `scripts/issue-cert.sh step1` / `step2` | Let's Encrypt via manual DNS-01 → `/opt/workshop/certs` |
| 3 | `scripts/build-student-repo.sh` | Builds the student history stage by stage from `student-repo/checkpoints.yaml`: the complete repo to `/opt/gitsrv/jarvis-all.git` (root-only) and the served `/opt/gitsrv/jarvis.git` released through the first stage (or wherever it already was). **Re-run the morning of class**: it regenerates Lab 02/03 data, whose window anchors to now. Refuses to publish if a leak assertion trips. A rebuild rewrites history: seats that already cloned need `reset-seats.sh` |
| - | `scripts/release-stage.sh` | **Day-of, on the host. THE command that releases a lab.** `release-stage.sh` (status) · `--next` · `stage-shadowai` · `--all`. Fast-forwards the served repo to that stage **and publishes the lab's `.html` on the share site**; students run `cd ~/jarvis && git pull` and the new lab appears. One-way. `share.sh` alone only moves documents |
| 3b | `scripts/start-llm-relay.sh` | Root systemd relay on `127.0.0.1:9010` holding the **Gravwell LLM token** for Lab 01b. Seats get the URL, never the token. The token comes from `../gravwell-llm.env` (git-ignored; copy `gravwell-llm.env.example`). Re-run with `restart` after rotating it |
| 4 | `scripts/makeuser.sh` | seats `workshop<ID>`; **default 2 seats, ids 10–11** (development / self-guided); `SEATS=20` for a full class, `START_ID=` to move the block |
| 5 | `scripts/preflight.sh` | read-only checklist; exits non-zero on any ❌ |
| - | `scripts/seat-survey.sh` | **Mid-class: where is the room?** Read-only. One row per seat: the stage their clone is on and whether they have pulled the current release, open SSH shells, their Gravwell and ingester containers, which Lab 05 proxies are actually listening, how much they have ingested, and the furthest lab with evidence on disk. `--tags` asks each seat's Gravwell which tags it holds and how many entries, which is the exact answer to "did the lab I just taught land". `--fast` skips the storage measurement, `--tsv` is machine-readable, and naming seat numbers surveys only those |
| - | `scripts/redeploy.sh` **(run on the authoring box)** | **You edited a lab? Run this.** Syncs the repo, rebuilds + ships the docs and refreshes the live share files, rebuilds the student repo at the same released stage, and updates every seat in place (`git reset --keep`, student edits kept). Reuses the existing lab data; `--regen` regenerates it (morning of class). `--reset-seats` to wipe instead, `--no-docs` for speed |
| - | `sync-repo.sh` **(run on the authoring box)** | Syncs the authoring repo to the host's `/opt/workshop/src`: the instructor-side working copy the runbook scripts run from. Syncs rather than delete-and-extract, and **forces `root:root`**: `tar -xz` preserves the archive's uids, and uid 1000 on the authoring box is *workshop10* on the host, which silently made every script root runs writable by a seat |
| - | `scripts/reset-seats.sh` | **Before every dry run and before class.** Returns each seat to never-used: removes its containers/volumes/networks (**including the separate `<ID>litellm` project**), wipes opencode/Claude Code state, and re-clones `~/jarvis`. Keeps the account, password, keys and `~/.workshop_env`. `--dry-run` to preview |
| - | `scripts/rmuser.sh` | teardown by seat range |
| - | `scripts/llm_relay.py` | The relay itself (stdlib Python, loopback-only, path allowlist, injects the bearer token) |
| 6 | `scripts/start-share-server.sh` | nginx-in-docker on 80/443 serving `$SHARE_ROOT/live` over HTTPS with basic auth + directory browsing. Verifies 401-without / 200-with |
| 7 | `deploy-share.sh` **(run on the authoring box)** | Builds `share/build/*.pdf` and ships them to the host's `staged/`. Refuses to ship instructor material |
| - | `scripts/share.sh` | **Day-of, on the host, for everything that is not a lab:** `share status` · `share publish slides/02-audit-gap` · `share publish --materials` · `share publish --all pdf` (take-home PDFs, end of day) · `share unpublish`. Labs go through `release-stage.sh`; publishing a lab page here alone warns that the seats lack the files. `--all` never releases the walkthroughs; those need `--walkthroughs` |
| - | `scripts/lab-stage-map.py` | Joins the two manifests: which share document belongs to which stage. Used by the two scripts above |
| - | `scripts/enable-semantic.sh` | Stands up the **P3 demo stack** (seat id 39): LLM ingester with a `vector` preprocessor + `[AI]` on the webserver, so `semantic` search works over `tag=llm`. `up` / `seed` / `down`. Instructor-only: it writes the model token into two configs |
| - | `scripts/start-gateway.sh` | **Not part of provisioning.** Reference implementation of a key-injecting gateway, for demonstrating the M9 architecture. See `api-key-architecture.md` |
| - | `scripts/mock_llm_upstream.py` | fake OpenAI/Anthropic provider for testing proxies without spending tokens |

### Accepted risks, and what to build next

- **Seats are in the `docker` group, which is root on the host.** File permissions keep the
  authoring copy, the unreleased PDFs and the secret files out of a seat's `ls` (`/opt/workshop` is
  `750`, `preflight.sh` checks it), but `docker run -v /:/host …` walks straight past that to
  `/opt/workshop/.env` and `gravwell-llm.env`. Accepted risk: every token on the box is
  short-lived and rotated per class, and rootless Docker per seat is a day of work plus a full
  revalidation. Do not "fix" this quietly by pulling seats out of the docker group; Lab 00 dies.
- **TODO: a `workshop-admin` Gravwell instance that ingests every command each attendee runs.**
  Shell history is the wrong source (a student can `unset HISTFILE`); use the kernel: auditd
  `execve` records (or Sysmon for Linux, which the course already teaches in Lab 03) shipped to an
  instructor-only Gravwell on the host, tagged per seat. That gives visibility on the docker risk
  above (a `docker run -v /:/host` shows up as an execve with those exact arguments), lets us catch a
  malicious or mischievous student during the class, and doubles as a live demo of the endpoint
  lesson: the instructors are auditing the room with the same telemetry the room just learned to
  read. Design notes: one Gravwell on a non-seat id (say 40) via the existing compose, an auditd
  rule for `execve` on uid ≥ 1000, the file follower or `simple_relay` for transport, a saved search
  per seat and one alert on `docker … -v /` / `sudo` / anything touching `/opt/workshop`.

### What lives where on the host

| Path | What it is |
|---|---|
| `/opt/gitsrv/jarvis.git` | **What students get.** Each seat clones it to `~/jarvis` at provisioning. Contains only the stages released so far (`release-stage.sh`); students `git pull` for the next lab |
| `/opt/gitsrv/jarvis-all.git` | The complete student history, root-only. `release-stage.sh` pushes from here into the served repo |
| `/opt/workshop/src` | Instructor-side working copy of the authoring repo, `root:root`. Runbook scripts execute from here. Delivered by `sync-repo.sh`. **Not student-facing** |
| `/opt/workshop/share/staged` | Every built PDF. **Never served** |
| `/opt/workshop/share/live` | The share site's web root, only what an instructor has released |
| `/opt/workshop/share/server` | The share server's compose file and `nginx.conf`, **copied out of the repo** so a running container never bind-mounts a file inside a tree that gets synced |
| `/opt/workshop/.env`, `gravwell-llm.env`, `certs/` | Secrets and TLS, root-only |

Secrets come from `/opt/workshop/.env` (copy of `.env.example`, `chmod 600`). Never committed.
Seats receive the real `ANTHROPIC_API_KEY` in `~/.workshop_env` (0600), see
[`api-key-architecture.md`](api-key-architecture.md) for why we don't proxy it, and how to rotate.
The **Gravwell LLM token** (Lab 01b) is the opposite case: it is proxied, by the root-only loopback
relay, and seats never see it. Same doc explains why the two differ.
Validated designs and gotchas: `gravwell-provisioning.md`.

### First thing on class day: whitelist the room's IP

**Before anyone logs in**, from inside the venue on the same wifi the students will use:

```
curl -s ifconfig.me
WORKSHOP_CLASS_IP=<that ip> /opt/workshop/src/instructor/runbook/scripts/bootstrap-host.sh
```

Every seat shares one NAT egress IP and password auth is on with a predictable seat password.
fail2ban's stock jail bans that IP after a handful of mistyped passwords **across the whole room**,
and its nftables rule rejects packets from *established* sessions too, so it does not merely block
reconnects, it drops all 20 students mid-lab and keeps them out for five minutes. `preflight.sh`
warns while this is unset; it is the one thing on the checklist that cannot be done in advance.

Pre-flight (day-of, from the original checklist): ingest corelight/sysmon samples on one
seat and run the Lab 02/03 searches; validate SSH + Gravwell login for a seat; confirm the LLM
ingester goes hot (`docker exec <ID>llm grep -i hot /opt/gravwell/log/llm_ingester.log`, **`docker logs`
is empty for this container**, it logs to a file inside).
