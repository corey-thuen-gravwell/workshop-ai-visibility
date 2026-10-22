#!/bin/bash
# Bring up the share server (nginx in docker) on the lab host. Run as root.
#
# Serves ONLY $SHARE_ROOT/live over HTTPS with basic auth and directory browsing. staged/ is not
# mounted, so unreleased material is unreachable rather than merely unlisted.
#
# The host's Traefik (/opt/webstack/stack) owns :80/:443. The share container publishes no ports;
# it joins Traefik's network ($TRAEFIK_NETWORK) and is routed by Host($SHARE_HOST), and Traefik
# issues that name's Let's Encrypt cert itself (HTTP-01), so SHARE_HOST must resolve to this host
# before the first request or Traefik serves its self-signed default.
#
#   ./start-share-server.sh            # write .htpasswd, bring it up, verify
#   ./start-share-server.sh restart
#   ./start-share-server.sh down
#
# Credentials come from SHARE_USER / SHARE_PASSWORD in /opt/workshop/.env, the name from SHARE_HOST
# (default share.$LAB_HOST).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"
SHARE_ROOT="${SHARE_ROOT:-/opt/workshop/share}"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-webstack-edge}"

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
SHARE_HOST="${SHARE_HOST:-${LAB_HOST:+share.$LAB_HOST}}"
[ -n "$SHARE_HOST" ] || { echo "SHARE_HOST (or LAB_HOST) not set in $ENV_FILE" >&2; exit 1; }

install -d -m 755 "$COMPOSE_DIR"
for f in docker-compose.yml nginx.conf; do
    if ! cmp -s "$REPO/share/server/$f" "$COMPOSE_DIR/$f"; then
        install -m 644 "$REPO/share/server/$f" "$COMPOSE_DIR/$f"
        echo "  updated $COMPOSE_DIR/$f: the container must be recreated to pick it up"
        RECREATE=1
    fi
done

cd "$COMPOSE_DIR"
export SHARE_ROOT SHARE_HOST TRAEFIK_NETWORK

case "${1:-up}" in
  down)    docker compose down 2>&1 | tail -2; exit 0 ;;
  restart) docker compose restart 2>&1 | tail -2 ;;
  up)
    [ -n "$SHARE_PASSWORD" ] || { echo "SHARE_PASSWORD not set in $ENV_FILE" >&2; exit 1; }
    docker network inspect "$TRAEFIK_NETWORK" >/dev/null 2>&1 \
        || { echo "docker network $TRAEFIK_NETWORK missing: is Traefik (/opt/webstack/stack) up?" >&2; exit 1; }
    getent hosts "$SHARE_HOST" >/dev/null \
        || echo "  !! $SHARE_HOST does not resolve yet: Traefik cannot get its cert until it does"

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
host="$SHARE_HOST"
# Through Traefik on this host, by name, so the Host() rule is what is being tested.
via=(--resolve "$host:443:127.0.0.1" --resolve "$host:80:127.0.0.1")
code_noauth=$(curl -sk "${via[@]}" -o /dev/null -w '%{http_code}' "https://$host/" || echo 000)
code_auth=$(curl -sk "${via[@]}" -o /dev/null -w '%{http_code}' -u "$SHARE_USER:$SHARE_PASSWORD" "https://$host/" || echo 000)
redir=$(curl -s "${via[@]}" -o /dev/null -w '%{http_code}' "http://$host/" || echo 000)
issuer=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$host" 2>/dev/null \
         | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//')

echo "  container:      $(docker inspect -f '{{.State.Status}}' workshop-share 2>/dev/null || echo missing)"
echo "  no credentials: HTTP $code_noauth   (want 401)"
echo "  with password:  HTTP $code_auth   (want 200)"
echo "  http -> https:  HTTP $redir   (want 301 or 308, from Traefik)"
echo "  cert issuer:    ${issuer:-none}   (want Let's Encrypt; TRAEFIK DEFAULT CERT = not issued yet)"
echo "  live items:     $(find "$SHARE_ROOT/live" -type f 2>/dev/null | wc -l)  ($(find "$SHARE_ROOT/live" -name '*.html' 2>/dev/null | wc -l) html, $(find "$SHARE_ROOT/live" -name '*.pdf' 2>/dev/null | wc -l) pdf)"
disk_i=$(stat -c %i "$COMPOSE_DIR/nginx.conf" 2>/dev/null)
cont_i=$(docker exec workshop-share stat -c %i /etc/nginx/conf.d/default.conf 2>/dev/null)
[ "$disk_i" = "$cont_i" ] && echo "  config:         live (inode matches disk)" \
                          || echo "  config:         STALE, container has $cont_i, disk has $disk_i; run: $0 restart"
echo "  URL:            https://$host/   user: $SHARE_USER"
[ "$code_noauth" = "401" ] && [ "$code_auth" = "200" ] \
    && echo "  OK: serving, and closed to anyone without the password." \
    || { echo "  PROBLEM: docker logs workshop-share"; exit 1; }
