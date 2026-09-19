# Lab 00: Environment onboarding & stand up Gravwell (docker)

## Objective
Get SSH'd in with a working docker environment, then stand up your own Gravwell instance in
docker: the log backend you will use for the rest of the class.

## Background
Every later lab assumes a running, licensed, reachable Gravwell that you control. You each get
your own instance rather than sharing one, so nothing you do can break anyone else's hunt, and
so the ports, configs and volumes in front of you are genuinely yours to break and rebuild.

## Setup
Your seat number lives in the environment as `WORKSHOPUID`, and **every port in this course is
built from it**. If `$WORKSHOPUID` is `14`, then `${WORKSHOPUID}443` is `14443` and
`${WORKSHOPUID}01` is `1401`. You can type `${WORKSHOPUID}443` literally; the shell substitutes it.

## Tasks
1. SSH to `workshop<ID>@<lab-host>` (the instructor gives you the host name, your seat number and
   your password). Working through this alone on your own machine? See `SETUP.md` at the repo root.
2. Verify the environment: `echo $WORKSHOPUID`, `docker run --rm hello-world`.
   If `$WORKSHOPUID` prints nothing, run `. ~/.workshop_env`.
3. Bring up Gravwell, **from the lab directory**, or docker has no compose file to read:
   ```bash
   cd ~/jarvis/labs/00-environment-gravwell
   docker compose up -d
   docker compose ps          # both containers should say Up
   ```
4. Browse to `https://<lab-host>:${WORKSHOPUID}443` and log in with **`admin` /
   `changeme`**. Open Query Studio and run:
   ```
   tag=gravwell limit 20
   ```
   Your timeline is **not** empty, but everything in it is the SIEM logging about *itself*. No
   security data arrives until Lab 02.
5. Mint the API token the rest of the course authenticates with, then load it into your shell:
   ```bash
   ./make-token.sh
   . ~/.workshop_env
   echo "${GRAVWELL_TOKEN:0:6}..."
   ```
   Every later script and `curl` in this course sends that token instead of logging in. Use it as
   its own header, which is **not** `Authorization: Bearer`:
   ```bash
   curl -sk https://localhost:${WORKSHOPUID}443/api/resources \
     -H "Gravwell-Token: $GRAVWELL_TOKEN" | jq length
   ```

### Why a token and not the password

A password login returns a JWT: it expires, and it is only as good as the password it came from.
Change your admin password (go ahead, it is your instance) and every script that logs in as
`admin`/`changeme` breaks with an auth error that has nothing to do with what you were doing. That
is not a lab-rig problem: it is why production automation holds a credential of its own.

The token is also scoped. `make-token.sh` asks your instance which capabilities exist and grants all
of them except token management, so this credential cannot mint another one. Gravwell treats token
capabilities as an overlay on your user's permissions: a token can only ever take access away, never
add it. Lab 06 comes back to this when an AI agent is the thing holding the credential.

## What you just started

Read `docker-compose.yml` while it comes up. It is short, and every choice in it is one you would
have to make yourself at home.

- **Named volumes** (`gwetc`, `gwstorage`) persist across `up`/`down` and initialize cleanly from
  the image. It does **not** bind-mount `/opt/gravwell/etc`: that fights the image (shadows
  configs, needs seeding, writes root-owned files into your home, ignores env config).
- **Config, license, and certs are layered in as read-only file-mounts** over the etc volume:
  - `config/https.conf` → HTTPS on 443
  - `config/simple_relay-corelight.conf` → the ingest listeners used in Lab 02
  - `config/simple_relay-litellm.conf` → raw-text listener for litellm container logs (Lab 05)
  - `config/simple_relay-shadowai-sources.conf` → osquery / SWG / CloudTrail / Workspace listeners
    for the beyond-the-wire lab (`<ID>11`–`<ID>14`)
  - `../../gravwell.license` → the Gravwell license (required, or nothing starts)
  - `${WORKSHOP_CERT_DIR}/cert.pem` + `key.pem` → the TLS cert. On an instructor-run lab host that is
    `/opt/workshop/certs` (root-owned, shared); self-hosted falls back to `./config/`.
- **Ports** derive from `WORKSHOPUID`: UI `${WORKSHOPUID}443` (HTTPS), litellm logs
  `${WORKSHOPUID}09`, corelight ingest `${WORKSHOPUID}01`–`04`, Python-proxy ingest
  `${WORKSHOPUID}05`, beyond-the-wire sources `${WORKSHOPUID}11`–`14`, LLM ingester
  `${WORKSHOPUID}80` / `81`.
- **Ingest auth:** `GRAVWELL_INGEST_AUTH` (indexer) and `GRAVWELL_INGEST_SECRET` (the bundled
  `simple_relay`) must be set to the *same* value from `.env` (default `IngestSecrets`). Set only
  one and `simple_relay` cannot talk to its own indexer.
- **LLM-ingester sidecar** (`<ID>llm`, official `gravwell/llm_ingester:5.10.1`) is part of the
  stack from the start, so Lab 05 is just "point opencode at it". It ingests to `gravwell:4023` over
  the compose network; nothing extra is published except its two listener ports.

## Gotchas worth knowing before you meet them

- **Never bind 514 or 601 in `simple_relay.conf.d`.** The stock image already defines `syslogtcp`
  (`tcp://0.0.0.0:601`) and `syslogudp` (`udp://0.0.0.0:514`). A duplicate bind fails config
  validation (`Bind-String … already in use`), **exits 0 three times, and then the manager sleeps
  for 10 minutes**: silently taking down *every* ingest listener, not just syslog. Debug with
  `docker exec <ID>gravwell /opt/gravwell/bin/gravwell_simple_relay -validate`.
- **litellm's logs go to a listener on `${WORKSHOPUID}09` with no `Reader-Type`**, raw
  line-delimited text. The built-in syslog listeners parse RFC5424 and silently drop docker's
  default RFC3164; Lab 05 only asks you to *look* at what a gateway records, not parse it, so not
  parsing is the simpler and more robust choice.
- The image serves the UI over **HTTPS on 443** only after the `https.conf` override + cert; its
  raw default is HTTP on `:80`.
- `simple_relay` benignly logs a few pipe-connect retries at startup until the indexer is up.
- Env vars (`WORKSHOPUID`, `WORKSHOP_CERT_DIR`) come from `~/.workshop_env`, sourced by both
  `.bashrc` and `.profile` so interactive **and** login shells get them. A fully non-interactive
  `ssh host 'cmd'` sources neither: pass the values explicitly in scripts.
- `permission denied … docker.sock` means your shell predates your docker group membership. Log
  out and back in.

## Checkpoint: if you get lost
Every lab has a **known-good snapshot** you can restore without losing anything you've done:

```bash
cd ~/jarvis && git checkout stage-gravwell -- labs/00-environment-gravwell
```

That overwrites the lab's files with the working versions and leaves you exactly where you are,
no branch switching, no detached HEAD, nothing else touched. Ask an instructor if you're unsure.

## Discussion
- You are running a SIEM, an ingest listener set and an LLM proxy on one box, from one compose
  file, in under a minute. What does that do to the argument that visibility work has to wait for
  a platform team?
- `tag=gravwell` is the tool logging about itself. Which of your own security tools emit their own
  audit trail, and does anyone read it?
