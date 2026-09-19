#!/bin/bash
# Create workshop seats on the lab host. Run as root.
#
# Seats are workshop<ID> for ID in [START_ID, START_ID+SEATS). Default: 2 seats, ids 10–11, the
# development/self-guided default. A delivery sets SEATS to the roster size (SEATS=20 ./makeuser.sh).
# IDs must stay in 10–49 (they prefix per-seat docker ports: <ID>443, <ID>514, <ID>01-04, ...).
#
# Secrets/values come from the environment or from an .env file (default: /opt/workshop/.env,
# see the repo's .env.example). Nothing is hardcoded.
#
# Usage:
#   ./makeuser.sh                          # 2 seats, ids 10-11, reads /opt/workshop/.env
#   SEATS=20 ./makeuser.sh                 # a full class, ids 10-29
#   SEATS=12 ./makeuser.sh                 # ids 10-21
#   START_ID=30 SEATS=5 ./makeuser.sh      # ids 30-34 (add a block later without touching others)
#   ENV_FILE=/path/.env ./makeuser.sh
#
# SECRETS: seats receive the real ANTHROPIC_API_KEY in ~/.workshop_env (0600). It is short-lived,
# spend-limited and revoked after the class. See runbook/api-key-architecture.md. For Lab 01b they
# receive only the loopback relay URL; the Gravwell LLM token stays root-only (start-llm-relay.sh).
set -euo pipefail
# The sudo -u <seat> calls below inherit our cwd; if that is inside /root, git fails with
# "failed to stat '/root/...': Permission denied" and set -e aborts after the first seat.
cd /

ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"
# What the operator passed wins over the .env file. Sourcing assigns unconditionally, so without
# this `SEATS=20 ./makeuser.sh` was silently overridden by the SEATS= line inside $ENV_FILE.
_cli_seats="${SEATS:-}"; _cli_start="${START_ID:-}"; _cli_end="${END_ID:-}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

SEATS="${_cli_seats:-${SEATS:-2}}"
START_ID="${_cli_start:-${START_ID:-10}}"
END_ID="${_cli_end:-${END_ID:-$((START_ID + SEATS - 1))}}"
REPO_PATH="${REPO_PATH:-/opt/gitsrv/jarvis.git}"
# Seats get the real provider key. The key is short-lived, spend-limited and
# revoked when the class ends, so engineering around student leakage costs more than it buys, and
# a gateway in front of everything stole Lab 05's key-boundary lesson. Students BUILD that boundary
# themselves in Lab 05 Part 2b. See instructor/runbook/api-key-architecture.md.
API_KEY="${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY (env or $ENV_FILE)}"
# Lab 01b: seats talk to the root-owned loopback relay (start-llm-relay.sh), which holds the token.
LLM_RELAY_LISTEN="${LLM_RELAY_LISTEN:-127.0.0.1:9010}"
WORKSHOP_USER_PASSWORD="${WORKSHOP_USER_PASSWORD:-}"        # empty => per-seat "<user>password"
GRAVWELL_INGEST_SECRET="${GRAVWELL_INGEST_SECRET:-IngestSecrets}"
INSTRUCTOR_KEYS="${INSTRUCTOR_KEYS:-/root/.ssh/authorized_keys}"
WORKSHOP_CERT_DIR="${WORKSHOP_CERT_DIR:-/opt/workshop/certs}"

if [ "$START_ID" -lt 10 ] || [ "$END_ID" -gt 49 ]; then
    echo "Seat ids must be within 10-49 (got $START_ID-$END_ID); they prefix docker ports." >&2; exit 1
fi
echo "Creating $((END_ID - START_ID + 1)) seats: workshop$START_ID .. workshop$END_ID"

for i in $(seq "$START_ID" "$END_ID"); do
    USERNAME="workshop$i"
    PASSWORD="${WORKSHOP_USER_PASSWORD:-${USERNAME}password}"
    USER_HOME="/home/$USERNAME"
    echo "== $USERNAME"

    # 1. User + password
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m -s /bin/bash "$USERNAME"
    fi
    echo "$USERNAME:$PASSWORD" | chpasswd

    # 2. Docker group
    usermod -aG docker "$USERNAME"

    # 3. Env vars -> ~/.workshop_env, sourced from .bashrc (before the non-interactive guard) and
    #    .profile so interactive and login shells both get them. Fully non-interactive
    #    `ssh host 'cmd'` sources neither: scripts must pass values explicitly.
    cat > "$USER_HOME/.workshop_env" <<ENV
# The workshop Anthropic key. Short-lived, spend-limited, revoked when the class ends.
export ANTHROPIC_API_KEY="$API_KEY"
export WORKSHOPUID="$i"
export WORKSHOP_CERT_DIR="$WORKSHOP_CERT_DIR"
export GRAVWELL_INGEST_SECRET="$GRAVWELL_INGEST_SECRET"
# Lab 01b: the loopback relay in front of the Gravwell-hosted model. No credential: the relay adds it.
export GRAVWELL_LLM_URL="http://$LLM_RELAY_LISTEN"
# Lab 00 mints a Gravwell API token into ~/.gravwell_token (make-token.sh). Export it here so every
# later shell and script has it without logging in again. Absent until that lab runs, and an if
# block rather than an && chain so sourcing this file never returns non-zero into a set -e script.
if [ -r "\$HOME/.gravwell_token" ]; then
    export GRAVWELL_TOKEN="\$(cat "\$HOME/.gravwell_token")"
fi
ENV
    chown "$USERNAME:$USERNAME" "$USER_HOME/.workshop_env"; chmod 600 "$USER_HOME/.workshop_env"
    grep -q '.workshop_env' "$USER_HOME/.bashrc" 2>/dev/null \
        || sed -i '1i [ -f ~/.workshop_env ] && . ~/.workshop_env' "$USER_HOME/.bashrc"
    grep -q '.workshop_env' "$USER_HOME/.profile" 2>/dev/null \
        || echo '[ -f ~/.workshop_env ] && . ~/.workshop_env' >> "$USER_HOME/.profile"

    # 4. Instructor SSH keys so instructors can SSH in as the student to help
    if [ -f "$INSTRUCTOR_KEYS" ]; then
        install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$USER_HOME/.ssh"
        cp "$INSTRUCTOR_KEYS" "$USER_HOME/.ssh/authorized_keys"
        chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh/authorized_keys"; chmod 600 "$USER_HOME/.ssh/authorized_keys"
    fi

    # 5. Git config + clone the student checkpoint repo (skips if the bare repo isn't built yet)
    sudo -u "$USERNAME" git config --global safe.directory '*'
    sudo -u "$USERNAME" git config --global pull.ff only
    sudo -u "$USERNAME" git config --global alias.adog 'log --all --decorate --oneline --graph'
    if [ -d "$REPO_PATH" ] && [ ! -d "$USER_HOME/jarvis" ]; then
        sudo -u "$USERNAME" git clone -q "$REPO_PATH" "$USER_HOME/jarvis"
    fi

    # 6. Smoke-test docker access (non-fatal)
    sudo -u "$USERNAME" docker ps >/dev/null 2>&1 || echo "   (docker not yet usable for $USERNAME: group applies at next login)"
done
echo "Done. Seats workshop$START_ID..workshop$END_ID ready."
