#!/bin/bash
# Return every seat to a pristine, never-used state. Run as root on the lab host.
#
# Use before a dry run or before the real class. Cheaper and more reliable than rmuser + makeuser:
# it keeps the accounts, passwords and instructor keys, and resets only what a student touches.
#
# What it clears, per seat:
#   - every container/volume/network belonging to that seat, INCLUDING the separate <ID>litellm
#     compose project (a `docker compose down` in labs/00 does not touch it)
#   - the ~/jarvis clone, re-cloned fresh from /opt/gitsrv/jarvis.git
#   - opencode and Claude Code state: stored credentials, session DBs, logs, caches. Leaving these
#     behind means the next person inherits somebody else's `opencode stats` and, worse, a stored
#     credential that silently outranks ANTHROPIC_API_KEY (that is a real Lab 04 failure mode).
#   - everything else in the home directory that is not a dotfile we put there
#
# What it does NOT touch: the account, the password, ~/.ssh, ~/.workshop_env, /opt/workshop.
#
#   ./reset-seats.sh                 # all seats (SEATS/START_ID as elsewhere)
#   ./reset-seats.sh --dry-run       # say what would go, delete nothing
#   SEATS=1 START_ID=29 ./reset-seats.sh
set -uo pipefail

SEATS="${SEATS:-2}"; START_ID="${START_ID:-10}"; END_ID="${END_ID:-$((START_ID + SEATS - 1))}"
REPO_PATH="${REPO_PATH:-/opt/gitsrv/jarvis.git}"
DRY=""; [ "${1:-}" = "--dry-run" ] && DRY=1

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
[ -d "$REPO_PATH" ] || { echo "missing $REPO_PATH: run build-student-repo.sh first" >&2; exit 1; }

say() { [ -n "$DRY" ] && printf '  would %s\n' "$*" || printf '  %s\n' "$*"; }
run() { [ -n "$DRY" ] || eval "$@"; }

total_c=0; total_f=0
for i in $(seq "$START_ID" "$END_ID"); do
    u="workshop$i"; h="/home/$u"
    id "$u" &>/dev/null || { echo "== $u (missing, skipped)"; continue; }
    echo "== $u"

    # containers first, or their volumes stay busy
    cs=$(docker ps -aq --filter "name=^${i}" 2>/dev/null | wc -l)
    if [ "$cs" -gt 0 ]; then
        say "remove $cs container(s)"
        run "docker rm -f \$(docker ps -aq --filter 'name=^${i}') >/dev/null 2>&1"
        total_c=$((total_c + cs))
    fi
    for v in $(docker volume ls -q 2>/dev/null | grep -E "^${i}(litellm)?_" ); do
        say "remove volume $v"; run "docker volume rm '$v' >/dev/null 2>&1"
    done
    for n in $(docker network ls --format '{{.Name}}' 2>/dev/null | grep -E "^${i}(litellm)?_"); do
        say "remove network $n"; run "docker network rm '$n' >/dev/null 2>&1"
    done

    # home: everything a student could have created
    leftovers=$(find "$h" -mindepth 1 -maxdepth 1 \
        ! -name '.ssh' ! -name '.workshop_env' ! -name '.bashrc' ! -name '.profile' \
        ! -name '.bash_logout' ! -name '.gitconfig' 2>/dev/null)
    n=$(echo "$leftovers" | grep -c . )
    [ "$n" -gt 0 ] && { say "clear $n item(s) from $h"; total_f=$((total_f + n)); }
    run "find '$h' -mindepth 1 -maxdepth 1 \
        ! -name '.ssh' ! -name '.workshop_env' ! -name '.bashrc' ! -name '.profile' \
        ! -name '.bash_logout' ! -name '.gitconfig' -exec rm -rf {} + 2>/dev/null"

    say "re-clone ~/jarvis"
    run "sudo -u '$u' git clone -q '$REPO_PATH' '$h/jarvis'"
done

echo
if [ -n "$DRY" ]; then
    echo "dry run: $total_c container(s), $total_f home item(s) would be removed across seats $START_ID-$END_ID"
    exit 0
fi
ok=0
for i in $(seq "$START_ID" "$END_ID"); do
    [ -f "/home/workshop$i/jarvis/labs/01-fundamentals/README.md" ] && ok=$((ok+1))
done
echo "reset $((END_ID - START_ID + 1)) seats: $total_c containers and $total_f home items removed"
echo "  $ok/$((END_ID - START_ID + 1)) seats have a working ~/jarvis clone"
strays=$(docker ps -aq --filter "name=^[0-9]" 2>/dev/null | wc -l)
echo "  $strays seat container(s) remaining (want 0)"
