#!/bin/bash
# Ship share/build/*.pdf from the authoring box to the lab host's staged/ directory.
#
# Run this FROM THE AUTHORING BOX (it is where the PDFs are built). Nothing is published by
# copying: staged/ is not mounted into the server. An instructor releases material with share.sh.
#
#   ./deploy-share.sh                 # build if needed, then ship to jarvis
#   HOST=other ./deploy-share.sh
#   ./deploy-share.sh --rebuild       # force a clean rebuild first
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="$REPO/share/build"
HOST="${HOST:-jarvis}"
SHARE_ROOT="${SHARE_ROOT:-/opt/workshop/share}"

[ "${1:-}" = "--rebuild" ] && make -C "$REPO/share" clean all
[ -d "$BUILD" ] || make -C "$REPO/share" all

count=$(find "$BUILD" -name '*.pdf' | wc -l)
html=$(find "$BUILD" -name '*.html' | wc -l)
[ "$count" -gt 0 ] || { echo "no PDFs in $BUILD, run: make -C share all" >&2; exit 1; }

# ---- refuse to ship anything that isn't a student-facing document ------------------------------
# .pdf = take-home; .html = the same document rendered for the browser with Copy buttons (the
# one students should work from during a lab: copying from a PDF breaks multi-line commands).
stray=$(find "$BUILD" -type f ! -name '*.pdf' ! -name '*.html' | head -5)
[ -z "$stray" ] || { echo "unexpected files in the build tree, refusing:" >&2; echo "$stray" >&2; exit 1; }

# Walkthroughs DO ship, an instructor may hand the full step-by-step to someone who is stuck:
# but only under walkthroughs/, where share.sh keeps them out of --all. Anything answer-shaped
# appearing elsewhere in the tree means the manifest is wrong, so fail loudly.
for bad in walkthrough instructor answer-key AGENDA; do
    hit=$(find "$BUILD" -type f -iname "*${bad}*" -not -path "$BUILD/walkthroughs/*" | head -3)
    [ -z "$hit" ] || { echo "refusing: '$bad' appears outside walkthroughs/:" >&2; echo "$hit" >&2; exit 1; }
done
wt=$(find "$BUILD/walkthroughs" -name '*.pdf' 2>/dev/null | wc -l)
[ "$wt" -eq 0 ] || echo "    (includes $wt walkthroughs: staged only; 'share publish --walkthroughs' releases them)"

echo "==> shipping $count PDFs + $html HTML pages ($(du -sh "$BUILD" | cut -f1)) to $HOST:$SHARE_ROOT/staged/"
tar -cz -C "$BUILD" . | ssh "$HOST" "
    set -e
    install -d -m 750 '$SHARE_ROOT/staged'
    install -d -m 755 '$SHARE_ROOT/live'
    rm -rf '$SHARE_ROOT/staged'/*
    # --no-same-owner + chown: a plain tar -xz kept the archive's uid 1000, which is workshop10 on
    # the lab host, so staged/ (the unreleased answer keys) was owned by and writable by a seat.
    # live/ stays 755: it is the bind-mount root the nginx worker traverses.
    tar -xz --no-same-owner -C '$SHARE_ROOT/staged'
    chown -R root:root '$SHARE_ROOT/staged'
    find '$SHARE_ROOT/staged' -type d -exec chmod 755 {} +
    find '$SHARE_ROOT/staged' -type f -exec chmod 644 {} +
    chmod 750 '$SHARE_ROOT/staged'
    stat -c '    staged owner: %U (want root)' '$SHARE_ROOT/staged'
    echo \"    staged: \$(find '$SHARE_ROOT/staged' -name '*.pdf' | wc -l) PDFs, \$(find '$SHARE_ROOT/staged' -name '*.html' | wc -l) HTML\"
    echo \"    live:   \$(find '$SHARE_ROOT/live' -type f 2>/dev/null | wc -l) files (unchanged, staged copies are newer; re-publish to refresh)\"
"
echo "==> done. Release material on the host with:  share status | share publish <name>"
