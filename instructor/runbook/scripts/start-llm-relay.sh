#!/bin/bash
# Install and start the Lab 01b LLM relay as a root systemd service. Run as root.
#
# This is the ONE process on the host that holds the Gravwell LLM token. It listens on loopback
# only; seats point at http://127.0.0.1:9010 with no credential at all, and the relay adds the
# bearer token on the way out. Students can use the model; they cannot see or take the token.
# (The Anthropic key is deliberately NOT handled this way, see api-key-architecture.md.)
#
# The token's source of truth is instructor/runbook/gravwell-llm.env (git-ignored: copy
# gravwell-llm.env.example and fill it in; rotate after every class). This script copies it to /opt/workshop/gravwell-llm.env
# (root, 0600), applying any override from /opt/workshop/.env, and the unit reads that file.
#
# Usage:
#   ./start-llm-relay.sh            # install unit, enable, start, verify
#   ./start-llm-relay.sh restart    # after rotating the token: edit the repo file, commit, run this
#   ./start-llm-relay.sh status
#   ./start-llm-relay.sh stop
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_ENV="${SRC_ENV:-$HERE/../gravwell-llm.env}"          # in the repo
ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"               # optional overrides
RELAY_ENV="${RELAY_ENV:-/opt/workshop/gravwell-llm.env}" # what the unit reads (root, 0600)
RELAY_BIN="${RELAY_BIN:-/opt/workshop/llm_relay.py}"
LISTEN="${LLM_RELAY_LISTEN:-127.0.0.1:9010}"
UNIT=/etc/systemd/system/workshop-llm-relay.service
SVC=workshop-llm-relay

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

case "${1:-install}" in
  status)  systemctl status "$SVC" --no-pager -l | head -20; exit 0 ;;
  stop)    systemctl disable --now "$SVC"; echo "stopped"; exit 0 ;;
  restart|install)
    [ -f "$SRC_ENV" ] || { echo "missing $SRC_ENV" >&2; exit 1; }
    # Resolve values: repo file first, /opt/workshop/.env overrides.
    ( set -a; . "$SRC_ENV"; [ -f "$ENV_FILE" ] && . "$ENV_FILE"; set +a
      : "${LLM_UPSTREAM_URL:?LLM_UPSTREAM_URL missing in $SRC_ENV}"
      : "${LLM_UPSTREAM_TOKEN:?LLM_UPSTREAM_TOKEN missing in $SRC_ENV}"
      umask 077
      printf 'LLM_UPSTREAM_URL=%s\nLLM_UPSTREAM_TOKEN=%s\n' "$LLM_UPSTREAM_URL" "$LLM_UPSTREAM_TOKEN" > "$RELAY_ENV" )
    chown root:root "$RELAY_ENV"; chmod 0600 "$RELAY_ENV"
    install -m 0755 -o root -g root "$HERE/llm_relay.py" "$RELAY_BIN"

    cat > "$UNIT" <<UNITEOF
[Unit]
Description=Workshop LLM relay for Lab 01b (loopback; holds the Gravwell LLM token)
Documentation=file:///opt/workshop/src/instructor/runbook/api-key-architecture.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=$RELAY_ENV
ExecStart=/usr/bin/python3 $RELAY_BIN --listen $LISTEN
Restart=always
RestartSec=3
# root on purpose: the env file is root:0600 and nothing else needs to read it.
User=root
Group=root
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
UNITEOF
    chmod 0644 "$UNIT"
    systemctl daemon-reload
    if [ "${1:-install}" = restart ]; then systemctl restart "$SVC"; else systemctl enable --now "$SVC"; fi
    sleep 2 ;;
  *) echo "usage: $0 [install|restart|status|stop]" >&2; exit 1 ;;
esac

# ---- verify: no credential needed from the client; other paths refused; loopback only
set +e
code_ok=$(curl -sS -o /dev/null -w '%{http_code}' -m 20 "http://$LISTEN/api/tags")
code_gen=$(curl -sS -o /dev/null -w '%{http_code}' -m 60 "http://$LISTEN/api/generate" \
    -H 'content-type: application/json' \
    -d '{"model":"logbot","prompt":"Reply OK","stream":false,"think":false,"options":{"num_predict":2}}')
code_bad=$(curl -sS -o /dev/null -w '%{http_code}' -m 10 "http://$LISTEN/api/version")
bound=$(ss -ltnH "sport = :${LISTEN##*:}" 2>/dev/null | awk '{print $4}' | tr '\n' ' ')
perm=$(stat -c '%U:%a' "$RELAY_ENV")

echo
echo "relay:           $(systemctl is-active "$SVC") / $(systemctl is-enabled "$SVC")"
echo "listening on:    ${bound:-?}   (want only 127.0.0.1:${LISTEN##*:})"
echo "token file:      $RELAY_ENV  $perm   (want root:600)"
echo "GET /api/tags:   HTTP $code_ok   (want 200, no token sent by the client)"
echo "POST /generate:  HTTP $code_gen  (want 200)"
echo "GET /api/version HTTP $code_bad  (want 403, not on the allowlist)"
[ "$code_ok" = 200 ] && [ "$code_gen" = 200 ] && [ "$code_bad" = 403 ] && [ "$perm" = "root:600" ] \
    && case "$bound" in *0.0.0.0*|*'*:'*|*'[::]'*) false;; *) true;; esac \
    && echo "OK: relay up, loopback-only, injecting the credential." \
    || { echo "PROBLEM, check: journalctl -u $SVC -n 30 --no-pager"; exit 1; }
