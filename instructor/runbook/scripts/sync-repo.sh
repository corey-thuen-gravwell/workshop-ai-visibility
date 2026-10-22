#!/bin/bash
# Sync the authoring repo to the lab host's /opt/workshop/src. Run FROM THE AUTHORING BOX.
#
# /opt/workshop/src is the instructor-side working copy the runbook scripts execute from. It is
# NOT what students get: they clone /opt/gitsrv/jarvis.git, which build-student-repo.sh produces.
#
# Why this is a script and not a one-line tar:
#   - It syncs rather than `rm -rf && extract`. The old way briefly deleted a tree that a running
#     container or a concurrent preflight might be reading, and replaced every file's inode even
#     when the content was identical.
#   - It forces root:root. `tar -xz` preserves the archive's uids, and uid 1000 on the authoring
#     box is *workshop10* on the lab host, which silently made every script root runs writable by
#     a seat user. That happened; do not undo this.
#
#   ./sync-repo.sh              # sync to jarvis
#   ./sync-repo.sh --dry-run    # show what would change
#   HOST=other ./sync-repo.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
HOST="${HOST:-jarvis}"
DEST="${DEST:-/opt/workshop/src}"
DRY=""; [ "${1:-}" = "--dry-run" ] && DRY="--dry-run"

# Build artifacts, generated data and secrets never leave the authoring box. Generated lab data
# in particular: the HOST generates it (build-student-repo.sh) with timestamps anchored to now,
# and redeploy.sh reuses the host's copy. Shipping the authoring box's stale copy over it put
# two-day-old Lab 02 data in front of a dry run. Never again.
# .devcontainer is the authoring sandbox (its keys/ holds deploy keys): never part of the course.
EXCLUDES=(--exclude=.git --exclude=.devcontainer --exclude=__pycache__ --exclude='*.pyc'
          --exclude=share/build --exclude=slides/build --exclude=.env
          --exclude='datasets/*/generated' --exclude='datasets/*/*/generated')
# Host-only files the authoring repo never carries (git-ignored secrets and the license). Excluded
# on the host side too, so --delete cannot remove them: without this, one sync took out the LLM
# token and every seat's Gravwell license.
PROTECT="--exclude=instructor/runbook/gravwell-llm.env --exclude=gravwell.license --exclude='*.license'"

echo "==> $REPO  ->  $HOST:$DEST"
# What is on the host, for preflight and for the next person: the authoring commit, and whether the
# working tree had uncommitted changes when it was shipped.
rev="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
[ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || rev="$rev+dirty"
printf '%s %s\n' "$rev" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REPO/.sync-rev"
trap 'rm -f "$REPO/.sync-rev"' EXIT
tar -cz "${EXCLUDES[@]}" -C "$REPO" . | ssh "$HOST" "
    set -e
    tmp=\$(mktemp -d /opt/workshop/.sync.XXXXXX)
    trap 'rm -rf \"\$tmp\"' EXIT
    tar -xz --no-same-owner -C \"\$tmp\"
    install -d -m 750 '$DEST'
    # -i itemizes, so a dry run actually tells you what would change
    rsync -ai --delete --exclude='datasets/*/generated' --exclude='datasets/*/*/generated' $PROTECT $DRY --chown=root:root \"\$tmp/\" '$DEST/' > \"\$tmp.log\"
    # every deletion in full (the itemized list is cut, deletions never are)
    grep '^\*deleting' \"\$tmp.log\" | sed 's/^/    /' || true
    grep -v '^\*deleting' \"\$tmp.log\" | sed 's/^/    /' | tail -25
    rm -f \"\$tmp.log\"
    if [ -z '$DRY' ]; then
        find '$DEST' -type d -exec chmod 755 {} +
        chmod 750 '$DEST'      # the tree itself is root-only; seats never read the authoring copy
        find '$DEST' -type f -exec chmod 644 {} +
        chmod 600 '$DEST/instructor/runbook/gravwell-llm.env' 2>/dev/null || true   # a token: root-only
        # Anything with a shebang is a script. (Matching *.sh/*.py by name silently stripped +x from
        # Lab 01b's *.bash files: 'Permission denied' on every seat.)
        { grep -rlZ --exclude-dir=.git '^#!' '$DEST' || true; } | xargs -0 -r chmod 755
        echo \"    owner: \$(stat -c %U:%G '$DEST')  files: \$(find '$DEST' -type f | wc -l)\"
        sudo -u workshop10 test -w '$DEST' && echo '    WARNING: a seat user can write to $DEST' || echo '    seats: read-only (correct)'
    fi
"
[ -n "$DRY" ] && { echo "==> dry run, nothing changed"; exit 0; }
echo "==> done"
echo "    If share/server/nginx.conf changed, apply it with: start-share-server.sh restart"
