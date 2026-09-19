#!/bin/bash
# Mint the Gravwell API token every later script in this course authenticates with.
#
# Why a token and not a login: a JWT from /api/login is tied to the password you typed and it
# expires. Change your admin password (which you are free to do) and every script that logs in as
# admin/changeme starts failing with a confusing auth error. A token is issued once, survives the
# password change, and can be revoked on its own.
#
#   ./make-token.sh                 # mint (or reuse) the token for YOUR seat
#   ./make-token.sh --show          # print the token you already have
#   ./make-token.sh --force         # mint a new one even if the current one works
#
# Instructor, for somebody else's seat, as root:
#   GW_URL=https://localhost:14443 TOKEN_FILE=/home/workshop14/.gravwell_token \
#   TOKEN_OWNER=workshop14 ./make-token.sh
#
# The token is written to ~/.gravwell_token (0600). ~/.workshop_env exports it as
# $GRAVWELL_TOKEN in every new shell, so scripts and handout commands can use
#   -H "Gravwell-Token: $GRAVWELL_TOKEN"
# NOTE: it is that header, not `Authorization: Bearer`. Gravwell answers a token sent as a bearer
# credential with 401 (verified 5.10.1).
set -euo pipefail

TOKEN_FILE="${TOKEN_FILE:-$HOME/.gravwell_token}"
TOKEN_NAME="${TOKEN_NAME:-workshop-automation}"
GW_USER="${GW_USER:-admin}"
GW_PASS="${GW_PASS:-changeme}"
TOKEN_OWNER="${TOKEN_OWNER:-}"

if [ -z "${GW_URL:-}" ]; then
    : "${WORKSHOPUID:?not set, run '. ~/.workshop_env' first}"
    GW_URL="https://localhost:${WORKSHOPUID}443"
fi

FORCE=0
case "${1:-}" in
    --show) [ -s "$TOKEN_FILE" ] && { cat "$TOKEN_FILE"; exit 0; }
            echo "no token yet: run $0" >&2; exit 1 ;;
    --force) FORCE=1 ;;
    "") ;;
    *) echo "usage: $0 [--show|--force]" >&2; exit 1 ;;
esac

works() {  # a token that can read resources is a token that works
    [ -n "${1:-}" ] || return 1
    [ "$(curl -sk -m 10 -o /dev/null -w '%{http_code}' "$GW_URL/api/resources" \
         -H "Gravwell-Token: $1")" = "200" ]
}

if [ "$FORCE" = 0 ] && [ -s "$TOKEN_FILE" ] && works "$(cat "$TOKEN_FILE")"; then
    echo "You already have a working token in $TOKEN_FILE. Nothing to do."
    exit 0
fi

# ---- log in once, with the password, to mint the thing that replaces the password ---------------
JWT=$(curl -sk -m 15 -X POST "$GW_URL/api/login" -H 'content-type: application/json' \
      -d "{\"User\":\"$GW_USER\",\"Pass\":\"$GW_PASS\"}" | sed -n 's/.*"JWT":"\([^"]*\)".*/\1/p')
if [ -z "$JWT" ]; then
    echo "Could not log in to $GW_URL as $GW_USER." >&2
    echo "  - Is your Gravwell up?   docker compose ps   (in labs/00-environment-gravwell)" >&2
    echo "  - Changed the password?  GW_PASS='your password' $0" >&2
    exit 1
fi
AUTH="Authorization: Bearer $JWT"

# Ask the instance which capabilities exist rather than hardcoding a list that drifts between
# versions. Everything except token management: this token does the course's work, and a leaked
# one still cannot mint a replacement for itself.
CAPS=$(curl -sk -m 15 "$GW_URL/api/tokens/capabilities" -H "$AUTH" \
       | jq -c '[.[] | select(. != "TokenRead" and . != "TokenWrite")]')
[ "$(printf '%s' "$CAPS" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ] \
    || { echo "could not read the capability list from $GW_URL" >&2; exit 1; }

TOKEN=$(curl -sk -m 15 -X POST "$GW_URL/api/tokens" -H "$AUTH" -H 'content-type: application/json' \
    -d "{\"Name\":\"$TOKEN_NAME\",\"Description\":\"course automation\",\"Capabilities\":$CAPS}" \
    | jq -r '.token // empty')
# Gravwell shows the token string exactly once, at creation. Write it before anything else can fail.
[ -n "$TOKEN" ] || { echo "token creation failed at $GW_URL/api/tokens" >&2; exit 1; }

umask 077
printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
if [ -n "$TOKEN_OWNER" ] && [ "$(id -u)" = 0 ]; then
    chown "$TOKEN_OWNER:$TOKEN_OWNER" "$TOKEN_FILE"
fi

works "$TOKEN" || { echo "token written to $TOKEN_FILE but it does not authenticate" >&2; exit 1; }

# Make sure ~/.workshop_env exports it, so every new shell has $GRAVWELL_TOKEN. makeuser.sh writes
# this block at provisioning; a seat provisioned before that existed self-heals here.
ENV_FILE_SEAT="${ENV_FILE_SEAT:-$(dirname "$TOKEN_FILE")/.workshop_env}"
if [ -w "$ENV_FILE_SEAT" ] && ! grep -q 'GRAVWELL_TOKEN' "$ENV_FILE_SEAT"; then
    cat >> "$ENV_FILE_SEAT" <<'ENVBLOCK'
if [ -r "$HOME/.gravwell_token" ]; then
    export GRAVWELL_TOKEN="$(cat "$HOME/.gravwell_token")"
fi
ENVBLOCK
fi

ncaps=$(printf '%s' "$CAPS" | jq length)
echo "Token created and verified: $TOKEN_FILE"
echo "  name: $TOKEN_NAME   capabilities: $ncaps (everything except token management)"
echo "Load it into this shell:   . ~/.workshop_env"
echo "Then use it:               -H \"Gravwell-Token: \$GRAVWELL_TOKEN\"  (not a bearer token)"
