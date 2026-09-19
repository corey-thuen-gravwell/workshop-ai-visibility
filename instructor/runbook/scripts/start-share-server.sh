#!/bin/bash
# Bring up the share server (nginx in docker) on the lab host. Run as root.
#
# Serves ONLY $SHARE_ROOT/live over HTTPS with basic auth and directory browsing. staged/ is not
# mounted, so unreleased material is unreachable rather than merely unlisted.
#
#   ./start-share-server.sh            # write .htpasswd, bring it up, verify
#   ./start-share-server.sh restart
#   ./start-share-server.sh down
#
# Credentials come from SHARE_USER / SHARE_PASSWORD in /opt/workshop/.env.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"
SHARE_ROOT="${SHARE_ROOT:-/opt/workshop/share}"
CERT_DIR="${WORKSHOP_CERT_DIR:-/opt/workshop/certs}"

# The server definition is COPIED out of the repo into a stable directory, and compose is run from
# there. A long-running container must not bind-mount a file inside the repo tree: syncing the repo
# replaces that file, the container keeps the old inode, and config edits then silently do not apply
# until someone recreates it. (Seen in testing: nginx was serving a config four
# hours older than the one on disk.) $SHARE_ROOT is never touched by a repo sync.
COMPOSE_DIR="${SHARE_SERVER_DIR:-$SHARE_ROOT/server}"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
SHARE_USER="${SHARE_USER:-workshop}"
SHARE_PASSWORD="${SHARE_PASSWORD:-}"

install -d -m 755 "$COMPOSE_DIR"
for f in docker-compose.yml nginx.conf; do
    if ! cmp -s "$REPO/share/server/$f" "$COMPOSE_DIR/$f"; then
        install -m 644 "$REPO/share/server/$f" "$COMPOSE_DIR/$f"
        echo "  updated $COMPOSE_DIR/$f: the container must be recreated to pick it up"
        RECREATE=1
    fi
done

cd "$COMPOSE_DIR"
export SHARE_ROOT WORKSHOP_CERT_DIR="$CERT_DIR"

case "${1:-up}" in
  down)    docker compose down 2>&1 | tail -2; exit 0 ;;
  restart) docker compose restart 2>&1 | tail -2 ;;
  up)
    [ -n "$SHARE_PASSWORD" ] || { echo "SHARE_PASSWORD not set in $ENV_FILE" >&2; exit 1; }
    [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/key.pem" ] \
        || { echo "no TLS cert at $CERT_DIR (issue-cert.sh)" >&2; exit 1; }

    install -d -m 755 "$SHARE_ROOT/staged" "$SHARE_ROOT/live"

    # nginx accepts apr1; openssl is already on the host, so no apache2-utils needed.
    printf '%s:%s\n' "$SHARE_USER" "$(openssl passwd -apr1 "$SHARE_PASSWORD")" > "$SHARE_ROOT/.htpasswd"
    chmod 644 "$SHARE_ROOT/.htpasswd"     # read inside the container by the nginx worker

    if [ -n "${RECREATE:-}" ]; then
        docker compose up -d --force-recreate 2>&1 | tail -3
    else
        docker compose up -d 2>&1 | tail -3
    fi
    ;;
  *) echo "usage: $0 [up|restart|down]" >&2; exit 1 ;;
esac

sleep 3
echo
host="${SHARE_HOST:-${LAB_HOST:-$(hostname -f)}}"
code_noauth=$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1/" || echo 000)
code_auth=$(curl -sk -o /dev/null -w '%{http_code}' -u "$SHARE_USER:$SHARE_PASSWORD" "https://127.0.0.1/" || echo 000)
redir=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1/" || echo 000)

echo "  container:      $(docker inspect -f '{{.State.Status}}' workshop-share 2>/dev/null || echo missing)"
echo "  no credentials: HTTP $code_noauth   (want 401)"
echo "  with password:  HTTP $code_auth   (want 200)"
echo "  http -> https:  HTTP $redir   (want 301)"
echo "  live items:     $(find "$SHARE_ROOT/live" -type f 2>/dev/null | wc -l)  ($(find "$SHARE_ROOT/live" -name '*.html' 2>/dev/null | wc -l) html, $(find "$SHARE_ROOT/live" -name '*.pdf' 2>/dev/null | wc -l) pdf)"
disk_i=$(stat -c %i "$COMPOSE_DIR/nginx.conf" 2>/dev/null)
cont_i=$(docker exec workshop-share stat -c %i /etc/nginx/conf.d/default.conf 2>/dev/null)
[ "$disk_i" = "$cont_i" ] && echo "  config:         live (inode matches disk)" \
                          || echo "  config:         STALE, container has $cont_i, disk has $disk_i; run: $0 restart"
echo "  URL:            https://$host/   user: $SHARE_USER"
[ "$code_noauth" = "401" ] && [ "$code_auth" = "200" ] \
    && echo "  OK: serving, and closed to anyone without the password." \
    || { echo "  PROBLEM: docker logs workshop-share"; exit 1; }
