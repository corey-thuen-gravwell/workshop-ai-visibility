# Gravwell stack config (mounted into the container)

- `https.conf`: serves the UI over HTTPS on 443 (drop-in for `gravwell.conf.d`). Committed.
  The search agent inside the image still expects the webserver on `http://127.0.0.1:80`, so the
  compose's `command:` rewrites `searchagent.conf` to `127.0.0.1:443` over HTTPS at every start.
  Without that, scheduled searches are accepted and never run. Check:
  `docker exec <ID>gravwell grep Webserver-Address /opt/gravwell/etc/searchagent.conf`.
- `simple_relay-corelight.conf`: per-tag ingest listeners for the shadow-AI data. Committed.
- `simple_relay-proxy.conf`, `-litellm.conf`, `-mcp.conf`, `-shadowai-sources.conf`, `-flag.conf`: one
  listener per later lab (the Python proxy, litellm, the student's MCP server, the beyond-the-wire
  sources, the Lab 07 flag). Each file says which lab feeds it. Committed.
- `cert.pem` / `key.pem`: TLS cert + private key. **Never committed** (git-ignored).

## Where the cert comes from

**On an instructor-run lab host:** a single Let's Encrypt cert for the host's DNS name lives at
`/opt/workshop/certs/`: root-owned (`key.pem` is `0600`), so the docker daemon can mount it into
every seat's container while seat users can't read the private key. Seats get
`WORKSHOP_CERT_DIR=/opt/workshop/certs` from `~/.workshop_env`, and the compose mounts from there.
One cert covers every instance because a cert is per-hostname, not per-port
(`:11443`, `:12443`, …). It is issued once per delivery by `instructor/runbook/scripts/issue-cert.sh`;
the lab host is disposable, so there is no renewal.

**Self-hosted (running this on your own box):** leave `WORKSHOP_CERT_DIR` unset, the compose falls
back to `./config/`. Drop your own `cert.pem`/`key.pem` here, or generate a self-signed pair:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout key.pem -out cert.pem -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"     # the recipe in SETUP.md section 4
```

The Gravwell license is mounted from `../../gravwell.license` (repo root, git-ignored; `SETUP.md`
section 2 explains the free-tier file and where to get a Community Edition one).
