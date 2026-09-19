#!/bin/bash
# Install and start the workshop LLM gateway as a systemd service. Run as root.
#
# This is the process that holds the REAL provider key. Seats never do: they hold WORKSHOP_TOKEN
# and point at 127.0.0.1:9000. See instructor/runbook/api-key-architecture.md.
#
# Bound to loopback on purpose: a leaked WORKSHOP_TOKEN is worthless off this host.
#
# Lab 01 depends on this being up (students curl http://127.0.0.1:9000/v1/messages), as does the
# seat-tier proxy in Lab 05 Part 2b.
#
# Usage:
#   ./start-gateway.sh            # install unit, enable, start, verify
#   ./start-gateway.sh status
#   ./start-gateway.sh restart    # e.g. after rotating the key in /opt/workshop/.env
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"
PROXY="${PROXY:-/opt/workshop/src/src/logging-proxy/llm_audit_proxy.py}"
LISTEN="${LISTEN:-127.0.0.1:9000}"
UPSTREAM="${UPSTREAM:-https://api.anthropic.com}"
LOG="${LOG:-/var/log/workshop-gateway.jsonl}"
UNIT=/etc/systemd/system/workshop-gateway.service

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

case "${1:-install}" in
  status)  systemctl status workshop-gateway --no-pager -l | head -20; exit 0 ;;
  restart) systemctl restart workshop-gateway; sleep 2 ;;
  install)
    [ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 1; }
    [ -f "$PROXY" ]    || { echo "missing $PROXY (run bootstrap-host.sh first)" >&2; exit 1; }
    grep -q '^ANTHROPIC_API_KEY="sk-ant-' "$ENV_FILE" \
        || { echo "ANTHROPIC_API_KEY missing/malformed in $ENV_FILE" >&2; exit 1; }

    cat > "$UNIT" <<UNITEOF
[Unit]
Description=Workshop LLM gateway (holds the provider key; seats present WORKSHOP_TOKEN)
Documentation=file:///opt/workshop/src/instructor/runbook/api-key-architecture.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/python3 $PROXY \\
    --listen $LISTEN \\
    --upstream $UPSTREAM \\
    --upstream-key \${ANTHROPIC_API_KEY} \\
    --client-key \${WORKSHOP_TOKEN} \\
    --log-file $LOG
Restart=always
RestartSec=3
# The key is only ever in this process's argv and environment, both root-only.
User=root
Group=root

[Install]
WantedBy=multi-user.target
UNITEOF
    chmod 0644 "$UNIT"
    systemctl daemon-reload
    systemctl enable --now workshop-gateway
    sleep 2 ;;
  *) echo "usage: $0 [install|restart|status]" >&2; exit 1 ;;
esac

# ---- verify: it must accept the workshop token and reject anything else
set +e
. "$ENV_FILE"
code_ok=$(curl -sS -o /dev/null -w '%{http_code}' -m 30 "http://$LISTEN/v1/messages" \
    -H "x-api-key: $WORKSHOP_TOKEN" -H 'anthropic-version: 2023-06-01' \
    -H 'content-type: application/json' \
    -d '{"model":"claude-haiku-4-5","max_tokens":8,"messages":[{"role":"user","content":"Reply OK"}]}')
code_bad=$(curl -sS -o /dev/null -w '%{http_code}' -m 15 "http://$LISTEN/v1/messages" \
    -H "x-api-key: definitely-wrong" -H 'anthropic-version: 2023-06-01' \
    -H 'content-type: application/json' \
    -d '{"model":"claude-haiku-4-5","max_tokens":8,"messages":[{"role":"user","content":"Reply OK"}]}')

echo
echo "gateway:        $(systemctl is-active workshop-gateway) / $(systemctl is-enabled workshop-gateway)"
echo "listening on:   $LISTEN"
echo "workshop token: HTTP $code_ok   (want 200)"
echo "wrong token:    HTTP $code_bad  (want 401)"
echo "log:            $LOG"
[ "$code_ok" = "200" ] && [ "$code_bad" = "401" ] \
    && echo "OK: the gateway is up and gating correctly." \
    || { echo "PROBLEM, check: journalctl -u workshop-gateway -n 30 --no-pager"; exit 1; }
