# Gravwell stack config (mounted into the container)

- `https.conf`: serves the UI over HTTPS on 443 (drop-in for `gravwell.conf.d`). Committed.
- `simple_relay-corelight.conf`: per-tag ingest listeners for the shadow-AI data. Committed.
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
docker run --rm -v "$PWD":/out gravwell/gravwell:latest \
  /opt/gravwell/bin/gencert -host localhost -cert-file /out/cert.pem -key-file /out/key.pem
```

The Gravwell license is mounted from `../../gravwell.license` (repo root, git-ignored; `SETUP.md`
explains where to get one).
